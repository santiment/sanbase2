defmodule Sanbase.Billing.Plan.Bundle.ItemSync do
  @moduledoc ~s"""
  What a Stripe webhook is allowed to do to a bundle subscription's items.

  Two jobs, both driven from `Sanbase.Billing.StripeEvent`:

    * `reconcile/2` - bring the local `subscription_items` back in line with the
      items Stripe reports, then re-resolve the entitlement. This is the
      `customer.subscription.updated` path, and also what a
      `customer.subscription.created` event does when the subscription is already
      known locally.
    * `sync_created/1` - the `customer.subscription.created` entry point. It
      reconciles a subscription we already have, and *adopts* one we do not: a
      bundle assembled straight in the Stripe dashboard has no local row, and
      without adoption the customer pays and receives nothing.

  Everything ends in `Bundle.Resolver.sync/1`, which recomputes the entitlement
  and the customer's `api_call_limits` row from the item rows rather than
  adjusting what is stored. That is what makes this safe to run repeatedly, which
  it has to be: one item change in Stripe produces several
  `customer.subscription.updated` events, and they are processed concurrently.

  ## Why a bundle is detected by price id

  A bundle's items are Stripe *Prices*, and their ids live only in
  `bundle_prices` - never in `plans.stripe_id`, because a `plans` row for a
  package price would be picked up by the upgrade/downgrade path and would hijack
  `subscriptions.plan_id` on every sync (§7.3 #2 of the handover doc). So the
  only reliable question to ask about a Stripe subscription is whether any of its
  item prices is in that catalog.

  **Any** item matching is enough. A subscription carrying one recognised package
  price plus something unrecognised is still a bundle; treating it as legacy
  would send it down the path that binds `subscriptions.plan_id` to whatever plan
  happens to be item[0], and Stripe does not guarantee item order.

  ## The guards, and what each one prevents

  Every one of these is a way this went wrong or could go wrong, not a
  precaution in the abstract.

    * **An unknown price id is skipped on reconcile and refuses adoption.**
      Reconciliation maintains a subscription whose other items are known, so an
      item it cannot name is left alone: deleting it would revoke something the
      customer is paying for and inventing a SKU for it would grant something
      they never bought. Adoption is the opposite situation - it has to write the
      whole purchased set from scratch, and a set with a hole in it is not the
      purchased set, so it refuses outright. Under no circumstances is a `plans`
      row created for a package price.

    * **A local row with `stripe_item_id: nil` is never deleted.**
      `Bundle.Lifecycle.add_item/3` inserts the local row *before* calling
      Stripe, on purpose: the `(subscription_id, sku)` unique index is then what
      settles two concurrent requests for the same SKU, rather than a read both
      of them can pass. Between those two steps the row is a claim Stripe has not
      heard of yet. Deleting it would let the second request through to create a
      second Stripe item the customer is billed for, and would make `add_item`'s
      own `Repo.update` on that row raise `Ecto.StaleEntryError`.

    * **An empty local item set is never populated by reconciliation.**
      `Lifecycle.subscribe/2` writes the subscription row and then its items, and
      Stripe's `created` and `updated` events can arrive inside that window.
      Inserting the items here would make its `persist_items/3` fail on the same
      unique index - and every failure after the charge cancels the Stripe
      subscription the customer has just paid for. Reconciliation repairs a set
      it already knows; adopting one is `sync_created/1`'s job and only for a
      subscription with no local row at all.

    * **`remove_at` is preserved on every row that survives.** An item scheduled
      for removal stays in Stripe until `Bundle.ItemExpiry` deletes it at the end
      of the paid period, so finding it in the Stripe item set is not evidence
      the customer changed their mind. Only `stripe_item_id` and an add-on's
      quantity are ever written to an existing row.

    * **A real `stripe_item_id` is never overwritten with `nil`.** A response
      that does not name the item is not evidence the item lost its id. Blanking
      it would make the row indistinguishable from a mid-flight claim - and
      therefore undeletable by the rule above - and leave nothing to address in
      Stripe when the item has to be re-priced or removed.

    * **Deletion keys on the SKU, not on the item id.** The rule is "the local
      row's SKU is not among the prices Stripe reports, and the row has a Stripe
      item id". Keying on "this row's `stripe_item_id` is absent from Stripe's
      item set" reads the same but is wrong: when Stripe replaces an item id for
      a price we still hold, that test deletes the row the repair pass was about
      to fix. Both formulations agree once ids are stable, and only the SKU one
      is order-independent.

    * **A package's quantity is pinned to 1.** Owning Market twice means nothing
      and `Subscription.Item` rejects it. An add-on's quantity is taken from
      Stripe, because that is what the customer is invoiced for and resolving
      fewer calls than were billed is silent under-delivery.

    * **Reconciliation is serialized per subscription.** The item set is read
      inside the transaction, after `FOR UPDATE` on the subscription row - the
      same lock and the same reason as `Resolver.sync/1`. Several
      `subscription.updated` events for one change are handled by separate tasks;
      two of them reading the item set before either wrote would both decide to
      insert the same SKU. The second run instead reads what the first committed
      and finds nothing to do.

    * **Adoption checks everything before the first insert.** Every price known,
      one billing interval, a `BUNDLE` marker plan for that interval, at least
      one package, and a published package snapshot to resolve against. A
      subscription row that exists but cannot be resolved is worse than none: the
      quota path raises on a bundle with no entitlement, so it would turn a
      customer with no access into a customer whose requests 500.
  """

  import Ecto.Query

  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Plan.Bundle.PackageSnapshot
  alias Sanbase.Billing.Plan.Bundle.Price
  alias Sanbase.Billing.Plan.Bundle.Resolver
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.Item
  alias Sanbase.Repo

  require Logger

  # `quantity` is whatever Stripe reported, including nothing at all - it is read
  # straight off the item and only `quantity_for/2` decides what it means.
  @type stripe_item :: %{
          stripe_item_id: String.t() | nil,
          price_id: String.t() | nil,
          quantity: pos_integer() | nil
        }

  @doc ~s"""
  Whether the Stripe subscription is a bundle - any of its item prices is in the
  local bundle catalog.
  """
  @spec bundle_stripe_subscription?(Stripe.Subscription.t() | map()) :: boolean()
  def bundle_stripe_subscription?(stripe_sub) do
    items = stripe_items(stripe_sub)
    prices = prices_for(items)

    Enum.any?(items, &known?(&1, prices))
  end

  @doc ~s"""
  Whether the local subscription is on a `BUNDLE` marker plan.

  Answered from the plan name through `Plan.type/1`, the one dispatch seam for
  plan types, rather than from the presence of item rows: a bundle whose items
  have not been written yet is still a bundle, and that is exactly the case the
  reconciliation has to recognise in order to refuse it.
  """
  @spec bundle_subscription?(Subscription.t()) :: boolean()
  def bundle_subscription?(%Subscription{} = subscription) do
    case Repo.preload(subscription, :plan) do
      %Subscription{plan: %Plan{name: name}} -> Plan.type(name) == :bundle
      _ -> false
    end
  end

  def bundle_subscription?(_), do: false

  @doc ~s"""
  Handle `customer.subscription.created` for a bundle Stripe subscription.

  Reconciles a subscription that is already known locally - the normal case,
  where `Bundle.Lifecycle.subscribe/2` created it moments earlier - and adopts
  one that is not.
  """
  @spec sync_created(Stripe.Subscription.t() | map()) ::
          {:ok, Subscription.t() | :not_reconciled} | {:error, term()}
  def sync_created(stripe_sub) do
    case Subscription.by_stripe_id(stripe_id(stripe_sub)) do
      %Subscription{} = subscription -> reconcile(subscription, stripe_sub)
      nil -> adopt(stripe_sub)
    end
  end

  @doc ~s"""
  Bring the local items in line with Stripe's, then re-resolve the entitlement.

  Returns `{:ok, :not_reconciled}` when the local item set is empty - see the
  guard on that in the moduledoc. Anything else that goes wrong is returned so
  the caller can leave the Stripe event unprocessed and visible.
  """
  @spec reconcile(Subscription.t(), Stripe.Subscription.t() | map()) ::
          {:ok, Subscription.t() | :not_reconciled} | {:error, term()}
  def reconcile(%Subscription{} = subscription, stripe_sub) do
    items = stripe_items(stripe_sub)
    prices = prices_for(items)
    {known, unknown} = Enum.split_with(items, &known?(&1, prices))

    Enum.each(unknown, &warn_unknown_price(subscription, &1))

    case apply_reconciliation(subscription, known, prices) do
      {:ok, :reconciled} -> Resolver.sync(subscription.id)
      {:ok, :not_reconciled} -> {:ok, :not_reconciled}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc ~s"""
  Rewrite the customer's `api_call_limits` row from their current subscriptions.

  Called after a bundle subscription is canceled. The entitlement and the items
  are deliberately left in place - access is already denied by the subscription
  status, and the rows are what a support ticket is answered from - but the quota
  row caches resolved numbers, so it has to be recomputed or the customer keeps a
  canceled bundle's call allowance.

  Always `:ok`. The status change that actually blocks access is already
  committed by this point, and a redelivery of the event would not conjure up a
  user row that could not be loaded.
  """
  @spec refresh_quota(Subscription.t()) :: :ok
  def refresh_quota(%Subscription{user_id: user_id}) do
    case User.by_id(user_id) do
      {:ok, user} ->
        Sanbase.ApiCallLimit.update_user_plan(user)
        :ok

      {:error, _reason} ->
        Logger.error("""
        [BundleItemSync] A bundle subscription for user id #{user_id} was canceled \
        but the user could not be loaded to refresh their api_call_limits row. \
        Their call quota keeps the bundle's numbers until the next plan change or \
        reconciliation run.
        """)

        :ok
    end
  end

  # --- adoption ---

  # A bundle that exists in Stripe and not here. Everything that can be checked
  # is checked before anything is written, the same order `Lifecycle.subscribe/2`
  # uses, because a subscription row whose entitlement cannot be resolved makes
  # the customer's requests raise rather than merely be refused.
  defp adopt(stripe_sub) do
    items = stripe_items(stripe_sub)
    prices = prices_for(items)

    with {:ok, user} <- fetch_customer(stripe_sub),
         :ok <- ensure_every_price_known(stripe_sub, items, prices),
         {:ok, interval} <- single_interval(items, prices),
         {:ok, plan} <- bundle_plan(interval),
         :ok <- ensure_a_package(items, prices),
         :ok <- ensure_snapshot_published() do
      case insert_subscription_with_items(stripe_sub, user, plan, items, prices) do
        {:ok, %Subscription{id: id}} ->
          Resolver.sync(id)

        {:error, :already_adopted} ->
          adopt_lost_race(stripe_sub)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp insert_subscription_with_items(stripe_sub, user, plan, items, prices) do
    Repo.transaction(fn ->
      case Subscription.create_subscription_db(stripe_sub, user, plan) do
        # `create_subscription_db/3` inserts with `on_conflict: :nothing`, so
        # another process that adopted the same `stripe_id` first is reported as a
        # row with no id rather than as an error. Carrying on would attach items
        # to nothing.
        {:ok, %Subscription{id: nil}} ->
          Repo.rollback(:already_adopted)

        {:ok, %Subscription{} = db_sub} ->
          Enum.each(items, fn item ->
            price = Map.fetch!(prices, item.price_id)
            insert_item(db_sub.id, price, item)
          end)

          db_sub

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  # Lost the insert race. Re-read rather than recurse: if the winner has not
  # committed yet there is nothing to reconcile, and the event is better left
  # unprocessed than spun on.
  defp adopt_lost_race(stripe_sub) do
    case Subscription.by_stripe_id(stripe_id(stripe_sub)) do
      %Subscription{} = subscription ->
        reconcile(subscription, stripe_sub)

      nil ->
        {:error,
         "Bundle subscription #{stripe_id(stripe_sub)} was adopted by another process " <>
           "that has not committed yet."}
    end
  end

  defp fetch_customer(stripe_sub) do
    case User.by_stripe_customer_id(customer_id(stripe_sub)) do
      {:ok, %User{} = user} -> {:ok, user}
      {:error, _reason} -> {:error, :customer_not_found}
    end
  end

  defp ensure_every_price_known(stripe_sub, items, prices) do
    case Enum.reject(items, &known?(&1, prices)) do
      [] ->
        :ok

      unknown ->
        {:error,
         "Bundle subscription #{stripe_id(stripe_sub)} cannot be adopted: " <>
           "#{length(unknown)} of its #{length(items)} Stripe item(s) reference prices " <>
           "that are not in the bundle catalog (#{inspect(Enum.map(unknown, & &1.price_id))}). " <>
           "Add them to bundle_prices - never to plans - and replay the event."}
    end
  end

  # Stripe bills one subscription on one interval, so disagreement here means the
  # catalog rows are wrong rather than the subscription. Guessing an interval
  # would put the subscription on the wrong marker plan and misreport it forever.
  defp single_interval(items, prices) do
    case items |> Enum.map(&Map.fetch!(prices, &1.price_id).interval) |> Enum.uniq() do
      [interval] ->
        {:ok, interval}

      [] ->
        {:error, "Bundle subscription has no items with a known price."}

      intervals ->
        {:error,
         "Bundle subscription mixes billing intervals (#{Enum.join(Enum.sort(intervals), ", ")}), " <>
           "which no marker plan can represent."}
    end
  end

  defp bundle_plan(interval) do
    case Plan.bundle_plan(interval) do
      %Plan{} = plan -> {:ok, plan}
      nil -> {:error, "BUNDLE plan for #{interval} is not configured"}
    end
  end

  # The resolver refuses an entitlement with no package behind it, and refusing
  # here means the refusal happens before a subscription row exists rather than
  # after.
  defp ensure_a_package(items, prices) do
    if Enum.any?(items, &(Map.fetch!(prices, &1.price_id).type == :package)) do
      :ok
    else
      {:error, "Bundle subscription has no package item, so it grants nothing."}
    end
  end

  defp ensure_snapshot_published do
    case PackageSnapshot.latest() do
      %PackageSnapshot{} ->
        :ok

      nil ->
        {:error,
         "No bundle package snapshot has been published, so an adopted bundle " <>
           "subscription could not be resolved."}
    end
  end

  # --- reconciliation ---

  # One transaction, so a partly reconciled item set cannot be observed or left
  # behind, and `FOR UPDATE` on the subscription row for the same reason
  # `Resolver.sync/1` takes it: one item change fires several
  # `subscription.updated` events, they are handled by separate tasks, and two
  # runs that both read the item set before either wrote would both try to insert
  # the same SKU. Locking first makes the second run read what the first
  # committed, so it finds nothing to do. The item set is therefore read *inside*
  # the transaction - reading it outside would put the lock after the decision it
  # is supposed to protect.
  #
  # `Resolver.sync/1` runs after this commits and takes the same lock again, in
  # the same order, so there is nothing to deadlock against.
  defp apply_reconciliation(subscription, stripe_items, prices) do
    Repo.transaction(fn ->
      lock_subscription(subscription.id)

      case Item.by_subscription(subscription.id) do
        [] ->
          warn_empty_local_items(subscription, stripe_items)
          :not_reconciled

        local ->
          do_reconcile(subscription, local, stripe_items, prices)
          :reconciled
      end
    end)
  end

  defp do_reconcile(subscription, local, stripe_items, prices) do
    local_by_sku = Map.new(local, &{&1.sku, &1})
    wanted = Enum.map(stripe_items, &{Map.fetch!(prices, &1.price_id), &1})
    wanted_skus = MapSet.new(wanted, fn {price, _stripe_item} -> price.sku end)

    Enum.each(wanted, fn {price, stripe_item} ->
      case Map.get(local_by_sku, price.sku) do
        nil -> insert_item(subscription.id, price, stripe_item)
        %Item{} = item -> repair_item(item, price, stripe_item)
      end
    end)

    local
    |> Enum.filter(&removed_in_stripe?(&1, wanted_skus))
    |> Enum.each(&delete_item(subscription, &1))
  end

  defp lock_subscription(subscription_id) do
    from(s in Subscription, where: s.id == ^subscription_id, lock: "FOR UPDATE")
    |> Repo.one()
  end

  # See the moduledoc: the SKU decides, and a row Stripe never heard of is a
  # claim in flight rather than a removal.
  defp removed_in_stripe?(%Item{stripe_item_id: nil}, _wanted_skus), do: false

  defp removed_in_stripe?(%Item{sku: sku}, wanted_skus),
    do: not MapSet.member?(wanted_skus, sku)

  # `mode: :savepoint` is load-bearing, not decoration. The duplicate below is
  # tolerated and the loop carries on, but without a savepoint Postgres has
  # already aborted the whole transaction by the time Ecto turns the unique
  # violation into a changeset error, and every statement after it fails with
  # `in_failed_sql_transaction` - so the "tolerated" case would take the rest of
  # the reconciliation down with it.
  #
  # `Repo.insert` rather than `Item.create/1` only because the latter takes no
  # options.
  defp insert_item(subscription_id, %Price{} = price, stripe_item) do
    attrs = %{
      subscription_id: subscription_id,
      stripe_item_id: stripe_item.stripe_item_id,
      sku: price.sku,
      type: price.type,
      quantity: quantity_for(price, stripe_item)
    }

    %Item{}
    |> Item.changeset(attrs)
    |> Repo.insert(mode: :savepoint)
    |> case do
      {:ok, item} ->
        Logger.info(
          "[BundleItemSync] Added #{price.sku} to subscription #{subscription_id} from Stripe."
        )

        item

      {:error, %Ecto.Changeset{} = changeset} ->
        # A concurrent `Lifecycle.add_item/3` claiming the same SKU - it does not
        # hold this subscription's lock, so it can still land here - is the outcome
        # this was converging on anyway, not an error. The row it created carries no
        # Stripe item id yet; the next event repairs that.
        if Item.duplicate_sku_error?(changeset) do
          :ok
        else
          Repo.rollback(changeset)
        end
    end
  end

  defp repair_item(%Item{} = item, %Price{} = price, stripe_item) do
    changes =
      %{}
      |> put_stripe_item_id(item, stripe_item)
      |> put_quantity(item, price, stripe_item)

    if changes == %{} do
      item
    else
      case item |> Item.changeset(changes) |> Repo.update() do
        {:ok, updated} -> updated
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end
  end

  defp delete_item(subscription, %Item{} = item) do
    Logger.info(
      "[BundleItemSync] #{item.sku} is gone from Stripe subscription " <>
        "#{subscription.stripe_id}; deleting item #{item.id}."
    )

    Repo.delete!(item)
  end

  defp put_stripe_item_id(changes, _item, %{stripe_item_id: nil}), do: changes

  defp put_stripe_item_id(changes, %Item{stripe_item_id: same}, %{stripe_item_id: same}),
    do: changes

  defp put_stripe_item_id(changes, %Item{}, %{stripe_item_id: id}),
    do: Map.put(changes, :stripe_item_id, id)

  defp put_quantity(changes, %Item{} = item, %Price{} = price, stripe_item) do
    quantity = quantity_for(price, stripe_item)

    if quantity == item.quantity do
      changes
    else
      Map.put(changes, :quantity, quantity)
    end
  end

  defp quantity_for(%Price{type: :package}, _stripe_item), do: 1

  defp quantity_for(%Price{}, %{quantity: quantity})
       when is_integer(quantity) and quantity > 0,
       do: quantity

  defp quantity_for(%Price{}, _stripe_item), do: 1

  # --- reading the Stripe object ---

  defp prices_for(items), do: Price.by_stripe_price_ids(Enum.map(items, & &1.price_id))

  defp known?(%{price_id: price_id}, prices), do: Map.has_key?(prices, price_id)

  defp stripe_items(%{items: %{data: data}}) when is_list(data) do
    Enum.map(data, fn item ->
      %{
        stripe_item_id: Map.get(item, :id),
        price_id: stripe_item_price_id(item),
        quantity: Map.get(item, :quantity)
      }
    end)
  end

  defp stripe_items(_), do: []

  # Deliberately reads `price` before `plan`. Stripe reports both on an item
  # created from a modern recurring Price, and only the `price` id is in the
  # bundle catalog. The `plan` fallback is what keeps a legacy single-item
  # subscription answering `false` to the bundle question instead of raising.
  #
  # The same shape exists privately in `Bundle.Lifecycle`. Kept separate rather
  # than shared, because that copy is about what our own purchase flow just
  # created and this one is about anything Stripe may report, including items no
  # code here made.
  defp stripe_item_price_id(item) do
    cond do
      match?(%{price: %{id: _}}, item) -> item.price.id
      match?(%{price: id} when is_binary(id), item) -> item.price
      match?(%{plan: %{id: _}}, item) -> item.plan.id
      true -> nil
    end
  end

  defp stripe_id(%{id: id}), do: id
  defp customer_id(%{customer: %{id: id}}), do: id
  defp customer_id(%{customer: customer}), do: customer

  # --- logging ---

  defp warn_unknown_price(subscription, %{price_id: price_id, stripe_item_id: stripe_item_id}) do
    Logger.error("""
    [BundleItemSync] Stripe subscription #{subscription.stripe_id} has item \
    #{inspect(stripe_item_id)} priced #{inspect(price_id)}, which is not in the bundle \
    catalog. It is being skipped: nothing here can say what SKU it is, and guessing \
    would either grant or revoke access the customer did not ask for. Add the price to \
    bundle_prices - never to plans - if it is meant to be sellable.
    """)
  end

  defp warn_empty_local_items(_subscription, []), do: :ok

  defp warn_empty_local_items(subscription, known) do
    Logger.warning("""
    [BundleItemSync] Subscription #{subscription.id} (#{subscription.stripe_id}) has no \
    local items while Stripe reports #{length(known)}. Not reconciling: a purchase in \
    flight writes the subscription row before its items, and inserting them here would \
    make it fail and cancel a subscription that has already been paid for. If this \
    persists, the purchase failed and was compensated, or the items need adopting by \
    hand.
    """)
  end
end
