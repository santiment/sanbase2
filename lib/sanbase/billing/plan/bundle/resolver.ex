defmodule Sanbase.Billing.Plan.Bundle.Resolver do
  @moduledoc ~s"""
  Works out what a bundle subscription is entitled to from what it bought.

  Two halves:

    * `resolve/2` - a pure function from items plus a package snapshot to
      entitlement attributes. No database, no Stripe, no clock.
    * `sync/1` - loads a subscription's items and the latest snapshot, resolves,
      and writes the result onto the subscription row.

  Splitting them that way is what makes the interesting part testable without any
  setup, and it is why `sync/1` is safe to call repeatedly: an item change in
  Stripe fires several `subscription.updated` events, and each one recomputes the
  same answer from scratch rather than adjusting what is already stored.

  ## The rules it applies

  All of these are decided (§6.3 and §9 of the handover doc):

    * **Metrics** - the union of the purchased packages, read from the snapshot.
    * **Queries and signals** - `"all"` for every bundle. They are effectively
      unrestricted today and packages do not change that (§6.4). It still has to
      be said explicitly, because the access map denies by default.
    * **Monthly API calls** - a flat 100,000 regardless of how many packages were
      bought, plus any add-on tiers. Deliberately not summed per package.
    * **Hourly and per-minute limits** - a single base value, never summed. Rate
      limits protect infrastructure; they are not a thing being sold, so buying
      more data must not raise burst capacity.
    * **Data windows** - full history and realtime for every bundle.

  ## What it refuses to do

  A subscription with no package items resolves to an error rather than an
  entitlement that grants nothing. An empty entitlement is indistinguishable from
  a working one at every later point, and would present as a paying customer
  whose every request is refused. An add-on with no package is the same mistake in
  a different shape.
  """

  import Ecto.Query

  alias Sanbase.Billing.Plan.Bundle.ApiCallAddon
  alias Sanbase.Billing.Plan.Bundle.Entitlement
  alias Sanbase.Billing.Plan.Bundle.Package
  alias Sanbase.Billing.Plan.Bundle.PackageSnapshot
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.Item
  alias Sanbase.Repo

  # Flat, not per package. Decided by product: choosing several packages still
  # gives one 100,000-call allowance.
  @base_calls_per_month 100_000

  # Reused from sanapi_pro (api_call_limit/restrictions.ex) so bundle burst
  # behavior matches the tier bundles are priced against.
  @base_calls_per_hour 30_000
  @base_calls_per_minute 600

  # Every bundle includes all the history there is, and realtime data.
  @historical_data_in_days nil
  @realtime_data_cut_off_in_days 0

  @type item :: %{sku: String.t(), type: :package | :api_calls, quantity: pos_integer()}

  @doc ~s"""
  The flat monthly call allowance every bundle starts from, before add-ons.
  """
  @spec base_calls_per_month() :: pos_integer()
  def base_calls_per_month, do: @base_calls_per_month

  @doc ~s"""
  Entitlement attributes for the given items, resolved against a package
  snapshot.

  Returns attributes rather than a struct so the result goes straight into
  `Sanbase.Billing.Subscription.bundle_entitlement_changeset/2` and is validated
  there rather than in two places.
  """
  @spec resolve([item()] | [Item.t()], PackageSnapshot.t()) ::
          {:ok, map()} | {:error, String.t()}
  def resolve(items, %PackageSnapshot{} = snapshot) when is_list(items) do
    with {:ok, packages} <- purchased_packages(items),
         {:ok, extra_calls} <- extra_calls(items) do
      {:ok,
       %{
         packages: packages,
         metric_access: %{
           "accessible" => PackageSnapshot.metrics_for(snapshot, packages),
           "accessible_patterns" => [],
           "not_accessible" => [],
           "not_accessible_patterns" => []
         },
         query_access: %{"accessible" => "all"},
         signal_access: %{"accessible" => "all"},
         api_call_limits: %{
           "month" => @base_calls_per_month + extra_calls,
           "hour" => @base_calls_per_hour,
           "minute" => @base_calls_per_minute
         },
         historical_data_in_days: @historical_data_in_days,
         realtime_data_cut_off_in_days: @realtime_data_cut_off_in_days,
         package_snapshot_version: snapshot.version,
         schema_version: Entitlement.current_schema_version()
       }}
    end
  end

  @doc ~s"""
  Recompute a subscription's entitlement from its items and store it.

  Idempotent: the answer is computed from scratch every time, so the repeated
  `subscription.updated` events a single item change produces are harmless.

  ## Why the row is locked

  Reading the items and writing the entitlement have to be one serialized unit.
  One item change in Stripe fires several `subscription.updated` events, and
  processed concurrently they interleave: a run that read the older item set can
  finish last and overwrite a newer, correct entitlement with a stale one. Since
  the value is a wholesale replacement rather than an increment, nothing would
  detect or repair that afterwards.

  `FOR UPDATE` on the subscription row makes concurrent syncs of the *same*
  subscription queue behind each other, so the last write is always the one that
  read the latest items. Syncs of different subscriptions are unaffected.
  """
  @spec sync(Subscription.t() | integer()) ::
          {:ok, Subscription.t()} | {:error, String.t() | Ecto.Changeset.t()}
  def sync(%Subscription{id: subscription_id}), do: sync(subscription_id)

  def sync(subscription_id) when is_integer(subscription_id) do
    Repo.transaction(fn ->
      case lock_subscription(subscription_id) do
        nil ->
          Repo.rollback("No subscription with id #{subscription_id}.")

        subscription ->
          with {:ok, snapshot} <- latest_snapshot(),
               items = Item.by_subscription(subscription_id),
               {:ok, attrs} <- resolve(items, snapshot),
               {:ok, updated} <-
                 subscription
                 |> Subscription.bundle_entitlement_changeset(attrs)
                 |> Repo.update() do
            updated
          else
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
  end

  # Re-read inside the transaction rather than trusting the struct a caller
  # handed in - it may already be stale, and the lock is only meaningful on a row
  # read within the transaction.
  defp lock_subscription(subscription_id) do
    from(s in Subscription, where: s.id == ^subscription_id, lock: "FOR UPDATE")
    |> Repo.one()
  end

  # Private

  defp latest_snapshot do
    case PackageSnapshot.latest() do
      nil ->
        {:error,
         """
         No bundle package snapshot has been published, so there is nothing to \
         resolve a bundle entitlement against. Publish one with \
         Sanbase.Billing.Plan.Bundle.PackageSnapshot.publish/1.
         """}

      snapshot ->
        {:ok, snapshot}
    end
  end

  defp purchased_packages(items) do
    packages =
      items
      |> Enum.filter(&(&1.type == :package))
      |> Enum.map(& &1.sku)
      |> Enum.uniq()

    case Enum.reject(packages, &Package.valid_slug?/1) do
      [] when packages == [] ->
        {:error,
         "A bundle subscription must include at least one package item. Got: #{inspect(Enum.map(items, & &1.sku))}."}

      [] ->
        # Sorted so the same purchase always produces the same stored value,
        # which keeps "did this change?" answerable by comparison.
        {:ok, Enum.sort(packages)}

      unknown ->
        {:error, "Unknown package(s): #{Enum.join(unknown, ", ")}."}
    end
  end

  defp extra_calls(items) do
    items
    |> Enum.filter(&(&1.type == :api_calls))
    |> Enum.reduce_while({:ok, 0}, fn item, {:ok, total} ->
      case ApiCallAddon.calls_per_month(item.sku) do
        {:ok, calls} -> {:cont, {:ok, total + calls * item.quantity}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end
end
