defmodule Sanbase.Billing.Plan.Bundle.ItemExpiry do
  @moduledoc ~s"""
  Finishes the removals that `Bundle.Lifecycle.remove_item/3` only scheduled.

  Dropping a package is not immediate: the customer paid for the period they are
  in, so the item keeps working and keeps being billed until that period ends.
  `remove_item/3` records the deadline in `subscription_items.remove_at` and
  stops there. This is what acts on it - deletes the item in Stripe so the next
  invoice is smaller, deletes the local row so the entitlement stops including
  it, and re-resolves the entitlement.

  Without this, `remove_item/3` is a promise nothing keeps: the customer would be
  billed for the package forever and keep its metrics forever.

  ## Runs on a schedule, not on a timer per item

  Scheduled from `config/scheduler_config.exs`, hourly. An item therefore goes
  away some time within the hour after its deadline, never before it. Sleeping
  until an exact moment would not survive a deploy, and paying for a few extra
  minutes is the safe direction to err in.

  ## Safe to run again

  Every step is idempotent. An item whose Stripe side is already gone counts as
  deleted (`resource_missing`), so a run that failed halfway finishes on the next
  pass. Anything that fails for another reason keeps its row and its deadline,
  and is retried an hour later rather than being silently dropped.
  """

  alias Sanbase.Billing.Plan.Bundle.Resolver
  alias Sanbase.Billing.Subscription.Item
  alias Sanbase.Repo
  alias Sanbase.StripeApi

  require Logger

  @type summary :: %{removed: non_neg_integer(), failed: non_neg_integer()}

  @doc ~s"""
  Remove every item whose deadline has passed.
  """
  @spec run(DateTime.t()) :: summary()
  def run(now \\ DateTime.utc_now()) do
    due = Item.due_for_removal(now)

    if due != [] do
      Logger.info("[BundleItemExpiry] #{length(due)} bundle item(s) due for removal.")
    end

    summary =
      due
      |> Enum.group_by(& &1.subscription_id)
      |> Enum.reduce(%{removed: 0, failed: 0}, fn {subscription_id, items}, acc ->
        merge_counts(acc, expire_subscription_items(subscription_id, items))
      end)

    if due != [] do
      Logger.info(
        "[BundleItemExpiry] Removed #{summary.removed} bundle item(s), " <>
          "#{summary.failed} failed."
      )
    end

    summary
  end

  defp expire_subscription_items(subscription_id, items) do
    counts =
      Enum.reduce(items, %{removed: 0, failed: 0}, fn item, acc ->
        case expire_item(item) do
          :ok -> Map.update!(acc, :removed, &(&1 + 1))
          :error -> Map.update!(acc, :failed, &(&1 + 1))
        end
      end)

    # Only worth re-resolving if something actually went away, and only once per
    # subscription no matter how many of its items expired together.
    if counts.removed > 0, do: resync(subscription_id)

    counts
  end

  defp expire_item(%Item{} = item) do
    case delete_in_stripe(item) do
      :ok ->
        case Repo.delete(item) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            # The Stripe item is gone but the row is not, so the entitlement still
            # grants it while the invoice no longer charges for it. Next run picks
            # the row up again and the Stripe delete is a no-op by then.
            report(item, "the local row could not be deleted", reason)
            :error
        end

      {:error, reason} ->
        report(item, "its Stripe item could not be deleted", reason)
        :error
    end
  end

  # `proration_behavior: "none"` because the deadline has already passed - the
  # customer used the whole period they paid for, so there is nothing to credit.
  # Prorating here would hand back money for time that was actually served.
  defp delete_in_stripe(%Item{stripe_item_id: stripe_item_id})
       when is_binary(stripe_item_id) do
    case StripeApi.delete_subscription_item(stripe_item_id, proration_behavior: "none") do
      {:ok, _} -> :ok
      {:error, %Stripe.Error{code: :resource_missing}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # An item that was never mirrored into Stripe has nothing to delete there.
  defp delete_in_stripe(%Item{}), do: :ok

  defp resync(subscription_id) do
    case Resolver.sync(subscription_id) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("""
        [BundleItemExpiry] Removed expired item(s) from subscription \
        #{subscription_id} but could not re-resolve its entitlement: \
        #{inspect(reason)}. The customer keeps the removed package until the next \
        successful sync.
        """)

        Sentry.capture_message("bundle_item_expiry_resync_failed",
          extra: %{subscription_id: subscription_id, reason: inspect(reason)}
        )

        :error
    end
  end

  defp report(%Item{} = item, what, reason) do
    Logger.error("""
    [BundleItemExpiry] Item #{item.id} (#{item.sku}) on subscription \
    #{item.subscription_id} was due for removal at #{item.remove_at} but #{what}: \
    #{inspect(reason)}. It will be retried on the next run.
    """)

    Sentry.capture_message("bundle_item_expiry_failed",
      extra: %{
        item_id: item.id,
        sku: item.sku,
        subscription_id: item.subscription_id,
        stripe_item_id: item.stripe_item_id,
        reason: inspect(reason)
      }
    )
  end

  defp merge_counts(left, right) do
    %{removed: left.removed + right.removed, failed: left.failed + right.failed}
  end
end
