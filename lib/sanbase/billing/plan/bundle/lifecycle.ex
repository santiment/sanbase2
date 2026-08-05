defmodule Sanbase.Billing.Plan.Bundle.Lifecycle do
  @moduledoc ~s"""
  Subscribe / add / remove / switch-interval / cancel for bundle subscriptions.

  Uses Stripe Subscription Items + Price ids from `Bundle.Price`. Writes local
  `subscription_items` and re-resolves entitlement via `Resolver.sync/1`.

  When the user already has a replaceable legacy SanAPI sub (`BUSINESS_PRO` /
  `BUSINESS_MAX`, or grandfathered `PRO` / `BASIC`), that sub is canceled with
  proration after the new bundle sub is created.
  """

  alias Sanbase.Accounts.User
  alias Sanbase.Billing
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Plan.Bundle.Price
  alias Sanbase.Billing.Plan.Bundle.Resolver
  alias Sanbase.Billing.Product
  alias Sanbase.Billing.Plan.SaleControls
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.Item
  alias Sanbase.Billing.Subscription.Query
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
         :ok <- ensure_can_subscribe_bundle(user),
         replaceable <- list_replaceable_sanapi_subs(user),
         {:ok, user} <- ensure_stripe_customer(user, card_token, payment_method_id),
         {:ok, stripe_sub} <- create_stripe_bundle_sub(user, prices, coupon),
         {:ok, db_sub} <- Subscription.create_subscription_db(stripe_sub, user, plan),
         :ok <- persist_items(db_sub, prices, stripe_sub),
         {:ok, db_sub} <- Resolver.sync(db_sub.id) do
      maybe_cancel_replaceable(replaceable)

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
         :ok <- ensure_sku_absent(sub, sku),
         {:ok, stripe_item} <-
           StripeApi.create_subscription_item(sub.stripe_id, price.stripe_price_id, []),
         {:ok, _} <-
           Item.create(%{
             subscription_id: sub.id,
             stripe_item_id: stripe_item.id,
             sku: price.sku,
             type: price.type,
             quantity: 1
           }),
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
         :ok <- ensure_not_last_package(sub, item),
         {:ok, _} <- mark_item_cancel_at_period_end(item),
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
         items <- Item.by_subscription(sub.id),
         {:ok, new_interval} <- counterpart_interval(sub.plan.interval),
         {:ok, new_plan} <- fetch_bundle_plan(new_interval),
         {:ok, new_prices} <- resolve_sellable_prices(Enum.map(items, & &1.sku), new_interval),
         {:ok, _stripe_sub} <- swap_stripe_items(sub, items, new_prices),
         {:ok, _} <- Subscription.update_subscription_db(sub, %{plan_id: new_plan.id}),
         :ok <- replace_local_items(sub.id, items, new_prices),
         {:ok, synced} <- Resolver.sync(sub.id) do
      {:ok, Subscription.by_id(synced.id)}
    end
  end

  @spec cancel(User.t(), integer()) ::
          {:ok, map()} | {:error, term()}
  def cancel(%User{} = user, subscription_id) do
    with {:ok, sub} <- fetch_owned_bundle(user, subscription_id),
         :ok <- validate_not_cancelling(sub),
         {:ok, result} <- Billing.cancel_subscription_at_period_end(sub) do
      {:ok, result}
    end
  end

  @doc ~s"""
  Whether the user may purchase a new SanAPI offering (Bundle / Institutional).

  Returns `:ok`, `{:replace, [subs]}` for replaceable legacy ladder subs, or an error.
  """
  @spec ensure_can_subscribe_bundle(User.t()) :: :ok | {:error, String.t()}
  def ensure_can_subscribe_bundle(%User{} = user) do
    case classify_active_sanapi(user) do
      {:ok, :none} -> :ok
      {:ok, :replaceable, _subs} -> :ok
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

  defp persist_items(db_sub, prices, stripe_sub) do
    stripe_items = stripe_items_by_price(stripe_sub)

    Enum.reduce_while(prices, :ok, fn price, :ok ->
      stripe_item_id =
        Map.get(stripe_items, price.stripe_price_id) ||
          "local_#{db_sub.id}_#{price.sku}"

      case Item.create(%{
             subscription_id: db_sub.id,
             stripe_item_id: stripe_item_id,
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
    Map.new(data, fn item ->
      price_id =
        cond do
          match?(%{price: %{id: _}}, item) -> item.price.id
          match?(%{price: id} when is_binary(id), item) -> item.price
          match?(%{plan: %{id: _}}, item) -> item.plan.id
          true -> nil
        end

      {price_id, item.id}
    end)
  end

  defp stripe_items_by_price(_), do: %{}

  defp maybe_cancel_replaceable([]), do: :ok

  defp maybe_cancel_replaceable(subs) do
    Enum.each(subs, fn sub ->
      case sub.stripe_id do
        id when is_binary(id) ->
          case StripeApi.cancel_subscription_with_proration(id) do
            {:ok, stripe_sub} ->
              Subscription.sync_subscription_with_stripe(stripe_sub, sub)

            {:error, reason} ->
              Logger.error(
                "Failed to cancel replaced SanAPI sub #{sub.id} after bundle subscribe: #{inspect(reason)}"
              )

              Sentry.capture_message("bundle_subscribe_replace_cancel_failed",
                extra: %{subscription_id: sub.id, reason: inspect(reason)}
              )
          end

        _ ->
          Subscription.update_subscription_db(sub, %{status: :canceled})
      end
    end)

    :ok
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

  defp ensure_sku_absent(sub, sku) do
    if Enum.any?(Item.by_subscription(sub.id), &(&1.sku == sku)) do
      {:error, "SKU #{sku} is already on this subscription"}
    else
      :ok
    end
  end

  defp fetch_item(sub, sku) do
    case Enum.find(Item.by_subscription(sub.id), &(&1.sku == sku)) do
      %Item{} = item -> {:ok, item}
      nil -> {:error, "SKU #{sku} is not on this subscription"}
    end
  end

  defp ensure_not_last_package(sub, %Item{type: :package}) do
    packages =
      Item.by_subscription(sub.id)
      |> Enum.filter(&(&1.type == :package and not &1.cancel_at_period_end))

    if length(packages) <= 1 do
      {:error, "Cannot remove the last package; cancel the subscription instead"}
    else
      :ok
    end
  end

  defp ensure_not_last_package(_sub, _item), do: :ok

  defp mark_item_cancel_at_period_end(%Item{} = item) do
    item
    |> Item.changeset(%{cancel_at_period_end: true})
    |> Repo.update()
  end

  defp counterpart_interval("month"), do: {:ok, "year"}
  defp counterpart_interval("year"), do: {:ok, "month"}
  defp counterpart_interval(_), do: {:error, "Unknown interval"}

  defp swap_stripe_items(sub, items, new_prices) do
    price_by_sku = Map.new(new_prices, &{&1.sku, &1})

    stripe_items =
      Enum.map(items, fn item ->
        new_price = Map.fetch!(price_by_sku, item.sku)

        cond do
          is_binary(item.stripe_item_id) and
              not String.starts_with?(item.stripe_item_id, "local_") ->
            %{id: item.stripe_item_id, price: new_price.stripe_price_id}

          true ->
            %{price: new_price.stripe_price_id}
        end
      end)

    StripeApi.update_subscription(sub.stripe_id, %{
      items: stripe_items,
      proration_behavior: "create_prorations"
    })
  end

  defp replace_local_items(subscription_id, old_items, new_prices) do
    Repo.transaction(fn ->
      Enum.each(old_items, fn item -> Repo.delete!(item) end)

      Enum.each(new_prices, fn price ->
        case Item.create(%{
               subscription_id: subscription_id,
               stripe_item_id: "local_#{subscription_id}_#{price.sku}_#{price.interval}",
               sku: price.sku,
               type: price.type,
               quantity: 1
             }) do
          {:ok, _} -> :ok
          {:error, changeset} -> Repo.rollback(changeset)
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
