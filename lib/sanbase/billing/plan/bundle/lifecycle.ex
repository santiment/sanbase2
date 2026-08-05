defmodule Sanbase.Billing.Plan.Bundle.Lifecycle do
  @moduledoc ~s"""
  Subscribe / add / remove / switch-interval / cancel for bundle subscriptions.

  Uses Stripe Subscription Items + Price ids from `Bundle.Price`. Writes local
  `subscription_items` and re-resolves entitlement via `Resolver.sync/1`.

  When the user already has a replaceable legacy SanAPI sub (`BUSINESS_PRO` /
  `BUSINESS_MAX`, or grandfathered `PRO` / `BASIC`), that sub is canceled with
  proration after the new bundle sub is created.

  ## Removing is scheduled, not immediate

  `remove_item/3` records a deadline on the item and returns. The customer paid
  for the period they are in, so the package keeps working and keeps being billed
  until it ends. `Sanbase.Billing.Plan.Bundle.ItemExpiry` is what deletes the
  Stripe item and the row once that moment passes.

  ## Everything that charges compensates

  Money moves before the local state is written - a Stripe subscription is
  created and the first invoice is paid, and only then can items fail to persist
  or the entitlement fail to resolve. Every such failure cancels the Stripe
  subscription it just created before returning the error, because the
  alternative is a customer who has paid and whose every request is refused.

  Anything that can be checked without charging is checked first, including that
  a package snapshot exists to resolve against.
  """

  import Ecto.Query

  alias Sanbase.Accounts.User
  alias Sanbase.Billing
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Plan.Bundle.PackageSnapshot
  alias Sanbase.Billing.Plan.Bundle.Price
  alias Sanbase.Billing.Plan.Bundle.Resolver
  alias Sanbase.Billing.Plan.SaleControls
  alias Sanbase.Billing.Product
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.Item
  alias Sanbase.Billing.Subscription.Query
  alias Sanbase.Billing.UserPromoCode
  alias Sanbase.Repo
  alias Sanbase.StripeApi

  require Logger

  @replaceable_plan_names ~w(BUSINESS_PRO BUSINESS_MAX PRO BASIC)
  @active_statuses [:active, :past_due, :trialing]

  @type interval :: String.t()
  @type subscribe_opts :: [
          packages: [String.t()],
          api_calls_addon: String.t() | nil,
          interval: interval(),
          card_token: String.t() | nil,
          payment_method_id: String.t() | nil,
          coupon: String.t() | nil
        ]

  @spec subscribe(User.t(), subscribe_opts()) ::
          {:ok, Subscription.t()} | {:error, term()}
  def subscribe(%User{} = user, opts) do
    packages = Keyword.fetch!(opts, :packages)
    interval = Keyword.fetch!(opts, :interval)
    api_calls_addon = Keyword.get(opts, :api_calls_addon)
    card_token = Keyword.get(opts, :card_token)
    payment_method_id = Keyword.get(opts, :payment_method_id)
    coupon = Keyword.get(opts, :coupon)

    with :ok <- ensure_offering_visible(user),
         :ok <- validate_packages(packages),
         :ok <- validate_interval(interval),
         {:ok, skus} <- build_skus(packages, api_calls_addon),
         {:ok, prices} <- resolve_sellable_prices(skus, interval),
         {:ok, plan} <- fetch_bundle_plan(interval),
         :ok <- ensure_snapshot_published(),
         :ok <- ensure_coupon_usable(coupon, plan),
         {:ok, replaceable} <- classify_for_subscribe(user),
         {:ok, user} <- ensure_stripe_customer(user, card_token, payment_method_id),
         {:ok, stripe_sub} <- create_stripe_bundle_sub(user, prices, coupon),
         {:ok, db_sub} <- store_subscription(stripe_sub, user, plan, prices) do
      cancel_replaceable(replaceable)

      {:ok, Subscription.by_id(db_sub.id)}
    end
  end

  @spec add_item(User.t(), integer(), String.t()) ::
          {:ok, Subscription.t()} | {:error, term()}
  def add_item(%User{} = user, subscription_id, sku) when is_binary(sku) do
    with :ok <- ensure_offering_visible(user),
         {:ok, sub} <- fetch_owned_bundle(user, subscription_id),
         :ok <- validate_not_cancelling(sub),
         {:ok, price} <- sellable_price_for_sub(sku, sub),
         {:ok, item} <- claim_item(sub, price),
         {:ok, _item} <- mirror_item_in_stripe(sub, item, price),
         {:ok, synced} <- Resolver.sync(sub.id) do
      {:ok, Subscription.by_id(synced.id)}
    end
  end

  @spec remove_item(User.t(), integer(), String.t()) ::
          {:ok, Subscription.t()} | {:error, term()}
  def remove_item(%User{} = user, subscription_id, sku) when is_binary(sku) do
    with :ok <- ensure_offering_visible(user),
         {:ok, sub} <- fetch_owned_bundle(user, subscription_id),
         :ok <- validate_not_cancelling(sub),
         {:ok, item} <- fetch_item(sub, sku),
         :ok <- ensure_not_already_removed(item),
         :ok <- ensure_not_last_package(sub, item),
         {:ok, _} <- schedule_item_removal(item, sub),
         {:ok, synced} <- Resolver.sync(sub.id) do
      {:ok, Subscription.by_id(synced.id)}
    end
  end

  @spec switch_interval(User.t(), integer()) ::
          {:ok, Subscription.t()} | {:error, term()}
  def switch_interval(%User{} = user, subscription_id) do
    with :ok <- ensure_offering_visible(user),
         {:ok, sub} <- fetch_owned_bundle(user, subscription_id),
         :ok <- validate_not_cancelling(sub),
         {:ok, staying, leaving} <- items_to_switch(sub),
         {:ok, new_interval} <- counterpart_interval(sub.plan.interval),
         {:ok, new_plan} <- fetch_bundle_plan(new_interval),
         {:ok, new_prices} <- resolve_sellable_prices(Enum.map(staying, & &1.sku), new_interval),
         {:ok, stripe_sub} <- swap_stripe_items(sub, staying, leaving, new_prices),
         :ok <- apply_interval_switch(sub, new_plan, staying, leaving, new_prices, stripe_sub),
         {:ok, synced} <- Resolver.sync(sub.id) do
      {:ok, Subscription.by_id(synced.id)}
    end
  end

  @spec cancel(User.t(), integer()) ::
          {:ok, map()} | {:error, term()}
  def cancel(%User{} = user, subscription_id) do
    # Deliberately not gated on `ensure_offering_visible/1`, unlike its four
    # siblings. Withdrawing the offering from sale must never trap the customers
    # who already bought it.
    with {:ok, sub} <- fetch_owned_bundle(user, subscription_id),
         :ok <- validate_not_cancelling(sub),
         {:ok, result} <- Billing.cancel_subscription_at_period_end(sub) do
      {:ok, result}
    end
  end

  @doc ~s"""
  Cancel legacy SanAPI subscriptions belonging to users who now have a bundle.

  The cancel at the end of `subscribe/2` can fail on its own - Stripe is down,
  the request times out - and it must not fail the purchase that has already been
  paid for. This is the retry, so a customer cannot be left paying for both the
  bundle and the plan it replaced.
  """
  @spec cancel_stale_replaced_subscriptions() :: %{
          canceled: non_neg_integer(),
          failed: non_neg_integer()
        }
  def cancel_stale_replaced_subscriptions do
    stale = stale_replaced_subscriptions()

    if stale != [] do
      Logger.info(
        "[BundleLifecycle] #{length(stale)} legacy SanAPI subscription(s) still active " <>
          "alongside a bundle."
      )
    end

    Enum.reduce(stale, %{canceled: 0, failed: 0}, fn sub, acc ->
      case cancel_replaced_subscription(sub) do
        :ok -> Map.update!(acc, :canceled, &(&1 + 1))
        :error -> Map.update!(acc, :failed, &(&1 + 1))
      end
    end)
  end

  @doc ~s"""
  Whether the user may purchase a new SanAPI offering (Bundle / Institutional).
  """
  @spec ensure_can_subscribe_bundle(User.t()) :: :ok | {:error, String.t()}
  def ensure_can_subscribe_bundle(%User{} = user) do
    case classify_for_subscribe(user) do
      {:ok, _subs} -> :ok
      {:error, _} = error -> error
    end
  end

  @spec list_replaceable_sanapi_subs(User.t()) :: [Subscription.t()]
  def list_replaceable_sanapi_subs(%User{} = user) do
    case classify_active_sanapi(user) do
      {:ok, :replaceable, subs} -> subs
      _ -> []
    end
  end

  # --- private ---

  defp ensure_offering_visible(user) do
    if SaleControls.bundle_plans_visible?(user) do
      :ok
    else
      {:error, "Bundle plans are not available for purchase yet"}
    end
  end

  defp validate_packages([]), do: {:error, "At least one package is required"}
  defp validate_packages(packages) when is_list(packages), do: :ok
  defp validate_packages(_), do: {:error, "packages must be a list"}

  defp validate_interval(interval) when interval in ["month", "year"], do: :ok
  defp validate_interval(_), do: {:error, "interval must be month or year"}

  defp build_skus(packages, nil), do: {:ok, Enum.uniq(packages)}

  defp build_skus(packages, addon) when is_binary(addon) do
    {:ok, Enum.uniq(packages ++ [addon])}
  end

  defp resolve_sellable_prices(skus, interval) do
    sellable = Price.sellable(interval) |> Map.new(&{&1.sku, &1})

    skus
    |> Enum.reduce_while({:ok, []}, fn sku, {:ok, acc} ->
      case Map.get(sellable, sku) do
        %Price{} = price -> {:cont, {:ok, [price | acc]}}
        nil -> {:halt, {:error, "SKU #{sku} is not sellable for #{interval}"}}
      end
    end)
    |> case do
      {:ok, prices} -> {:ok, Enum.reverse(prices)}
      error -> error
    end
  end

  defp fetch_bundle_plan(interval) do
    case Plan.bundle_plan(interval) do
      %Plan{} = plan -> {:ok, plan}
      nil -> {:error, "BUNDLE plan for #{interval} is not configured"}
    end
  end

  # Checked before charging rather than discovered after. Resolving an entitlement
  # needs a published snapshot, and without one the customer would be billed for a
  # subscription that grants nothing.
  defp ensure_snapshot_published do
    case PackageSnapshot.latest() do
      %PackageSnapshot{} ->
        :ok

      nil ->
        {:error,
         "The bundle package catalog has not been published yet, so a bundle cannot be sold"}
    end
  end

  # The standard `subscribe` mutation validates the coupon before charging. The
  # bundle flow has to do the same, or a code that is expired, exhausted or
  # restricted to another product is redeemed against our own counter and only
  # then argued about with Stripe.
  defp ensure_coupon_usable(nil, _plan), do: :ok

  defp ensure_coupon_usable(coupon, %Plan{} = plan) do
    case UserPromoCode.is_coupon_usable(coupon, plan) do
      true -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_stripe_customer(user, _card_token, payment_method_id)
       when is_binary(payment_method_id) do
    StripeApi.attach_payment_method_to_customer(user, payment_method_id)
  end

  defp ensure_stripe_customer(user, card_token, _payment_method_id) do
    Billing.create_or_update_stripe_customer(user, card_token)
  end

  defp create_stripe_bundle_sub(user, prices, coupon) do
    items = Enum.map(prices, fn %Price{stripe_price_id: id} -> %{price: id} end)

    params = %{
      customer: user.stripe_customer_id,
      items: items,
      off_session: true
    }

    params =
      if coupon do
        Map.put(params, :coupon, coupon)
      else
        params
      end

    StripeApi.create_bundle_subscription(params)
  end

  # Everything after the charge. Any failure here cancels the subscription that
  # was just paid for, because a bundle with no items or no entitlement refuses
  # every request the customer makes.
  defp store_subscription(stripe_sub, user, plan, prices) do
    with {:ok, db_sub} <- Subscription.create_subscription_db(stripe_sub, user, plan),
         :ok <- ensure_sole_bundle_subscription(db_sub, user),
         :ok <- persist_items(db_sub, prices, stripe_sub),
         {:ok, db_sub} <- Resolver.sync(db_sub.id) do
      {:ok, db_sub}
    else
      {:error, reason} ->
        abort_stripe_subscription(stripe_sub, reason)
        {:error, reason}
    end
  end

  # Two requests that arrive together both pass the "no active SanAPI
  # subscription" check before either has inserted anything, and both then create
  # a Stripe subscription. Rather than lock around a call to Stripe, both rows are
  # allowed to land and the loser withdraws: the lowest id wins, so exactly one
  # survives no matter which order the two finish in.
  defp ensure_sole_bundle_subscription(%Subscription{id: id}, user) do
    winner =
      user
      |> active_bundle_subscription_ids()
      |> Enum.min(fn -> id end)

    if winner == id do
      :ok
    else
      {:error,
       "Another bundle subscription for this account was created at the same time. " <>
         "This one was withdrawn - reload and use the existing subscription."}
    end
  end

  defp abort_stripe_subscription(%Stripe.Subscription{id: stripe_id}, reason) do
    Logger.error("""
    [BundleLifecycle] Bundle subscription #{stripe_id} was created and charged but \
    could not be set up locally: #{inspect(reason)}. Cancelling it with proration.
    """)

    Sentry.capture_message("bundle_subscribe_rolled_back",
      extra: %{stripe_subscription_id: stripe_id, reason: inspect(reason)}
    )

    case StripeApi.cancel_subscription_with_proration(stripe_id) do
      {:ok, _} ->
        cancel_local_subscription(stripe_id)
        :ok

      {:error, cancel_reason} ->
        # The customer has been charged for a subscription we could not set up and
        # could not cancel. Nothing here can fix that; a human has to.
        Logger.error("""
        [BundleLifecycle] Bundle subscription #{stripe_id} could not be cancelled \
        after a failed setup: #{inspect(cancel_reason)}. It is charging the customer \
        and grants nothing - cancel and refund it by hand.
        """)

        Sentry.capture_message("bundle_subscribe_rollback_failed",
          extra: %{stripe_subscription_id: stripe_id, reason: inspect(cancel_reason)}
        )

        :error
    end
  end

  defp cancel_local_subscription(stripe_id) do
    case Subscription.by_stripe_id(stripe_id) do
      %Subscription{} = sub -> Subscription.update_subscription_db(sub, %{status: :canceled})
      nil -> :ok
    end
  end

  # `stripe_item_id` is left nil when Stripe's response does not name the item for
  # a price, rather than filled with something that looks like a Stripe id but is
  # not. A synthetic id cannot be used to change or delete anything, and every
  # later caller would have to know the difference.
  defp persist_items(db_sub, prices, stripe_sub) do
    stripe_items = stripe_items_by_price(stripe_sub)

    Enum.reduce_while(prices, :ok, fn price, :ok ->
      case Item.create(%{
             subscription_id: db_sub.id,
             stripe_item_id: Map.get(stripe_items, price.stripe_price_id),
             sku: price.sku,
             type: price.type,
             quantity: 1
           }) do
        {:ok, _} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp stripe_items_by_price(%Stripe.Subscription{items: %Stripe.List{data: data}}) do
    data
    |> Enum.map(fn item -> {stripe_item_price_id(item), item.id} end)
    |> Enum.reject(fn {price_id, _item_id} -> is_nil(price_id) end)
    |> Map.new()
  end

  defp stripe_items_by_price(_), do: %{}

  defp stripe_item_price_id(item) do
    cond do
      match?(%{price: %{id: _}}, item) -> item.price.id
      match?(%{price: id} when is_binary(id), item) -> item.price
      match?(%{plan: %{id: _}}, item) -> item.plan.id
      true -> nil
    end
  end

  defp cancel_replaceable([]), do: :ok

  defp cancel_replaceable(subs) do
    Enum.each(subs, &cancel_replaced_subscription/1)

    :ok
  end

  # Never fails the purchase. The new subscription is paid for and valid; the old
  # one lingering is a billing problem to be retried, which
  # `cancel_stale_replaced_subscriptions/0` does on a schedule.
  defp cancel_replaced_subscription(%Subscription{stripe_id: stripe_id} = sub)
       when is_binary(stripe_id) do
    case StripeApi.cancel_subscription_with_proration(stripe_id) do
      {:ok, stripe_sub} ->
        Subscription.sync_subscription_with_stripe(stripe_sub, sub)
        :ok

      {:error, reason} ->
        Logger.error(
          "[BundleLifecycle] Failed to cancel replaced SanAPI sub #{sub.id} after bundle " <>
            "subscribe: #{inspect(reason)}. Will be retried."
        )

        Sentry.capture_message("bundle_subscribe_replace_cancel_failed",
          extra: %{subscription_id: sub.id, reason: inspect(reason)}
        )

        :error
    end
  end

  # No Stripe object to cancel - a locally created row, so marking it is the whole
  # job.
  defp cancel_replaced_subscription(%Subscription{} = sub) do
    case Subscription.update_subscription_db(sub, %{status: :canceled}) do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end

  # `not is_nil(s.stripe_id)` is the whole safety of this job. It exists to finish
  # a replacement that `subscribe/2` started, and only a real Stripe purchase can
  # have started one. Bundle rows created by hand in the admin panel have no
  # Stripe object, and without this condition a test bundle handed to a real
  # account would cancel that customer's genuine, paid SanAPI subscription an hour
  # later - with proration, in Stripe, unprompted.
  defp stale_replaced_subscriptions do
    product_api = Product.product_api()

    on_new_offering =
      from(s in Subscription,
        join: p in Plan,
        on: s.plan_id == p.id,
        where:
          s.status in ^@active_statuses and p.product_id == ^product_api and
            not is_nil(s.stripe_id) and
            (like(p.name, "BUNDLE%") or like(p.name, "INSTITUTIONAL%")),
        select: s.user_id
      )

    from(s in Subscription,
      join: p in Plan,
      on: s.plan_id == p.id,
      where:
        s.status in ^@active_statuses and p.product_id == ^product_api and
          p.name in ^@replaceable_plan_names and s.user_id in subquery(on_new_offering),
      preload: [plan: :product]
    )
    |> Repo.all()
  end

  defp classify_for_subscribe(user) do
    case classify_active_sanapi(user) do
      {:ok, :none} -> {:ok, []}
      {:ok, :replaceable, subs} -> {:ok, subs}
      {:error, _} = error -> error
    end
  end

  defp classify_active_sanapi(%User{id: user_id}) do
    subs =
      Subscription
      |> Query.user_has_any_subscriptions_for_product(user_id, Product.product_api())
      |> Query.join_plan_and_product()
      |> Repo.all()
      |> Enum.filter(fn s -> s.status in @active_statuses end)

    cond do
      subs == [] ->
        {:ok, :none}

      Enum.any?(subs, &custom_plan?/1) ->
        {:error, "Active custom/enterprise SanAPI subscription cannot be auto-replaced"}

      Enum.any?(subs, &new_offering_plan?/1) ->
        {:error, "You already have an active SanAPI subscription on the new offering"}

      Enum.any?(subs, &replaceable_plan?/1) ->
        {:ok, :replaceable, Enum.filter(subs, &replaceable_plan?/1)}

      true ->
        {:error, "You already have an active SanAPI subscription"}
    end
  end

  defp active_bundle_subscription_ids(%User{id: user_id}) do
    Subscription
    |> Query.user_has_any_subscriptions_for_product(user_id, Product.product_api())
    |> Query.join_plan_and_product()
    |> Repo.all()
    |> Enum.filter(fn s -> s.status in @active_statuses and new_offering_plan?(s) end)
    |> Enum.map(& &1.id)
  end

  defp custom_plan?(%Subscription{plan: %Plan{name: "CUSTOM_" <> _}}), do: true
  defp custom_plan?(_), do: false

  defp new_offering_plan?(%Subscription{plan: %Plan{name: "BUNDLE" <> _}}), do: true
  defp new_offering_plan?(%Subscription{plan: %Plan{name: "INSTITUTIONAL" <> _}}), do: true
  defp new_offering_plan?(_), do: false

  defp replaceable_plan?(%Subscription{plan: %Plan{name: name}})
       when name in @replaceable_plan_names,
       do: true

  defp replaceable_plan?(_), do: false

  defp fetch_owned_bundle(%User{id: user_id}, subscription_id) do
    case Subscription.by_id(subscription_id) do
      %Subscription{user_id: ^user_id, plan: %Plan{name: name}} = sub ->
        if Plan.type(name) == :bundle do
          {:ok, Repo.preload(sub, plan: :product)}
        else
          {:error, "Subscription is not a bundle"}
        end

      %Subscription{} ->
        {:error, "Subscription does not belong to the user"}

      nil ->
        {:error, "Subscription not found"}
    end
  end

  defp validate_not_cancelling(%Subscription{cancel_at_period_end: true}) do
    {:error, "Subscription is already scheduled for cancellation"}
  end

  defp validate_not_cancelling(_), do: :ok

  defp sellable_price_for_sub(sku, %Subscription{plan: %Plan{interval: interval}}) do
    case Price.sellable(interval) |> Enum.find(&(&1.sku == sku)) do
      %Price{} = price -> {:ok, price}
      nil -> {:error, "SKU #{sku} is not sellable for #{interval}"}
    end
  end

  # The local row is written before Stripe is called so the unique index on
  # (subscription_id, sku) is what decides a race, not a read that two requests
  # can both pass. The loser is rejected before it can create a second Stripe item
  # the customer would be billed for.
  defp claim_item(sub, price) do
    case Item.create(%{
           subscription_id: sub.id,
           sku: price.sku,
           type: price.type,
           quantity: 1
         }) do
      {:ok, item} ->
        {:ok, item}

      {:error, %Ecto.Changeset{} = changeset} = error ->
        if duplicate_sku?(changeset) do
          {:error, "SKU #{price.sku} is already on this subscription"}
        else
          error
        end
    end
  end

  # The unique index covers (subscription_id, sku), so Ecto reports the violation
  # against `subscription_id` - the first field named - not against `sku`. Matching
  # the constraint by name says what is meant regardless.
  defp duplicate_sku?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_message, opts}} ->
      Keyword.get(opts, :constraint_name) == "subscription_items_subscription_id_sku_index"
    end)
  end

  defp mirror_item_in_stripe(sub, %Item{} = item, price) do
    case StripeApi.create_subscription_item(sub.stripe_id, price.stripe_price_id, []) do
      {:ok, stripe_item} ->
        item
        |> Item.changeset(%{stripe_item_id: stripe_item.id})
        |> Repo.update()

      {:error, reason} ->
        # Undo the claim, otherwise the customer holds a package Stripe never
        # billed them for and cannot retry adding it.
        Repo.delete(item)
        {:error, reason}
    end
  end

  defp fetch_item(sub, sku) do
    case Enum.find(Item.by_subscription(sub.id), &(&1.sku == sku)) do
      %Item{} = item -> {:ok, item}
      nil -> {:error, "SKU #{sku} is not on this subscription"}
    end
  end

  defp ensure_not_already_removed(%Item{sku: sku} = item) do
    if Item.scheduled_for_removal?(item) do
      {:error, "SKU #{sku} is already scheduled for removal"}
    else
      :ok
    end
  end

  defp ensure_not_last_package(sub, %Item{type: :package}) do
    staying = Item.staying_on_subscription(sub.id) |> Enum.filter(&(&1.type == :package))

    if length(staying) <= 1 do
      {:error, "Cannot remove the last package; cancel the subscription instead"}
    else
      :ok
    end
  end

  defp ensure_not_last_package(_sub, _item), do: :ok

  # A locally created subscription has no billing period, so there is nothing to
  # wait for and the removal is due at once.
  defp schedule_item_removal(%Item{} = item, %Subscription{current_period_end: period_end}) do
    remove_at = period_end || DateTime.utc_now()

    item
    |> Item.changeset(%{remove_at: remove_at})
    |> Repo.update()
  end

  defp items_to_switch(sub) do
    all = Item.by_subscription(sub.id)
    {leaving, staying} = Enum.split_with(all, &Item.scheduled_for_removal?/1)

    if staying == [] do
      {:error, "This subscription has no items to switch"}
    else
      {:ok, staying, leaving}
    end
  end

  defp counterpart_interval("month"), do: {:ok, "year"}
  defp counterpart_interval("year"), do: {:ok, "month"}
  defp counterpart_interval(_), do: {:error, "Unknown interval"}

  # Items already scheduled for removal are dropped here rather than re-priced.
  # Carrying them over would undo the customer's removal, and there is no period
  # left to honour once the subscription is billed on a different cycle.
  defp swap_stripe_items(sub, staying, leaving, new_prices) do
    price_by_sku = Map.new(new_prices, &{&1.sku, &1})

    repriced =
      Enum.map(staying, fn item ->
        new_price = Map.fetch!(price_by_sku, item.sku)

        case item.stripe_item_id do
          id when is_binary(id) -> %{id: id, price: new_price.stripe_price_id}
          nil -> %{price: new_price.stripe_price_id}
        end
      end)

    deleted =
      leaving
      |> Enum.filter(&is_binary(&1.stripe_item_id))
      |> Enum.map(&%{id: &1.stripe_item_id, deleted: true})

    StripeApi.update_subscription(sub.stripe_id, %{
      items: repriced ++ deleted,
      proration_behavior: "create_prorations"
    })
  end

  # The item ids Stripe reports back are the authority. Changing an item's price
  # keeps its id, but reading them from the response also repairs any row that had
  # none, and is what lets a second switch address the existing items instead of
  # asking Stripe to add more alongside them.
  #
  # One transaction, because a subscription whose plan says one interval while its
  # items are priced on the other cannot be told apart from a correct one later.
  defp apply_interval_switch(sub, new_plan, staying, leaving, new_prices, stripe_sub) do
    item_id_by_price = stripe_items_by_price(stripe_sub)
    price_id_by_sku = Map.new(new_prices, &{&1.sku, &1.stripe_price_id})

    Repo.transaction(fn ->
      case Subscription.update_subscription_db(sub, %{plan_id: new_plan.id}) do
        {:ok, _} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end

      Enum.each(leaving, &Repo.delete!/1)

      Enum.each(staying, fn item ->
        new_item_id = Map.get(item_id_by_price, Map.get(price_id_by_sku, item.sku))

        if is_binary(new_item_id) and new_item_id != item.stripe_item_id do
          item
          |> Item.changeset(%{stripe_item_id: new_item_id})
          |> Repo.update!()
        end
      end)

      :ok
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
