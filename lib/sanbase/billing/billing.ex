defmodule Sanbase.Billing do
  @moduledoc ~s"""
  Context module for all billing functionality
  """

  import Ecto.Query
  import Sanbase.Billing.EventEmitter, only: [emit_event: 3]

  alias Sanbase.Repo
  alias Sanbase.Billing.{Product, Plan, Subscription}
  alias Sanbase.Billing.Subscription.LiquiditySubscription
  alias Sanbase.Billing.Subscription.ProPlus
  alias Sanbase.Accounts.User
  alias Sanbase.StripeApi

  # Subscription API
  defdelegate subscribe(user, plan, card, coupon), to: Subscription
  defdelegate update_subscription(subscription, plan), to: Subscription
  defdelegate cancel_subscription(subscription), to: Subscription
  defdelegate renew_cancelled_subscription(subscription), to: Subscription

  defdelegate sync_stripe_subscriptions, to: Subscription
  defdelegate remove_duplicate_subscriptions, to: Subscription

  # LiquiditySubscription
  defdelegate create_liquidity_subscription(user_id), to: LiquiditySubscription
  defdelegate remove_liquidity_subscription(liquidity_subscription), to: LiquiditySubscription
  defdelegate list_liquidity_subscriptions, to: LiquiditySubscription
  defdelegate eligible_for_liquidity_subscription?(user_id), to: LiquiditySubscription
  defdelegate user_has_active_sanbase_subscriptions?(user_id), to: LiquiditySubscription
  defdelegate sync_liquidity_subscriptions_staked_users, to: LiquiditySubscription
  defdelegate maybe_create_liquidity_subscriptions_staked_users, to: LiquiditySubscription
  defdelegate maybe_remove_liquidity_subscriptions_staked_users, to: LiquiditySubscription

  # ProPlus
  defdelegate create_free_basic_api, to: ProPlus
  defdelegate delete_free_basic_api, to: ProPlus

  def list_products(), do: Repo.all(Product)

  def list_plans() do
    from(p in Plan, preload: [:product])
    |> Repo.all()
  end

  def eligible_for_sanbase_trial?(user_id) do
    Subscription.all_user_subscriptions_for_product(user_id, Product.product_sanbase())
    |> Enum.empty?()
  end

  def eligible_for_api_trial?(user_id) do
    Subscription.all_user_subscriptions_for_product(user_id, Product.product_api())
    |> Enum.empty?()
  end

  @doc ~s"""
  Sync the locally defined Products and Plans with stripe.

  This acction assigns a `stripe_id` to every product and plan without which
  no subscription can succeed.

  In order to create the Products and Plans locally, the seed
  `priv/repo/seed_plans_and_products.exs` must be executed.
  """
  @spec sync_products_with_stripe() :: :ok | {:error, %Stripe.Error{}}
  def sync_products_with_stripe() do
    with :ok <- run_sync(list_products(), &Product.maybe_create_product_in_stripe/1),
         :ok <- run_sync(list_plans(), &Plan.maybe_create_plan_in_stripe/1) do
      :ok
    else
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  If user has enough SAN staked and has no active Sanbase subscription - create one
  """
  @spec maybe_create_liquidity_subscription(non_neg_integer()) ::
          {:ok, %Subscription{}} | {:error, any()} | false
  def maybe_create_liquidity_subscription(user_id) do
    eligible_for_liquidity_subscription?(user_id) && create_liquidity_subscription(user_id)
  end

  # Private functions

  # Return :ok if all function calls over the list return {:ok, _}
  # Return the error otherwise
  defp run_sync(list, function) when is_function(function, 1) do
    Enum.map(list, function)
    |> Enum.find(:ok, fn
      {:ok, _} -> false
      {:error, _} -> true
    end)
  end

  @spec create_or_update_stripe_customer(%User{}, String.t() | nil) ::
          {:ok, %User{}} | {:error, %Stripe.Error{}}
  def create_or_update_stripe_customer(user, card_token \\ nil)

  def create_or_update_stripe_customer(%User{stripe_customer_id: nil} = user, card_token) do
    with {:ok, stripe_customer} = result <- StripeApi.create_customer_with_card(user, card_token) do
      emit_event(result, :create_stripe_customer, %{user: user, card_token: card_token})

      User.update_field(user, :stripe_customer_id, stripe_customer.id)
    end
  end

  def create_or_update_stripe_customer(%User{stripe_customer_id: stripe_id} = user, nil)
      when is_binary(stripe_id) do
    {:ok, user}
  end

  def create_or_update_stripe_customer(%User{stripe_customer_id: stripe_id} = user, card_token)
      when is_binary(stripe_id) do
    with {:ok, _} = result <- StripeApi.update_customer_card(user, card_token) do
      emit_event(result, :update_stripe_customer, %{user: user, card_token: card_token})

      {:ok, user}
    end
  end

  def get_sanbase_pro_user_ids() do
    sanbase_user_ids_mapset =
      Subscription.get_direct_sanbase_pro_user_ids()
      |> MapSet.new()

    linked_user_id_pairs = Sanbase.Accounts.LinkedUser.get_all_user_id_pairs()

    user_ids_inherited_sanbase_pro =
      Enum.reduce(linked_user_id_pairs, MapSet.new(), fn pair, acc ->
        {primary_user_id, secondary_user_id} = pair

        case primary_user_id in sanbase_user_ids_mapset do
          true -> MapSet.put(acc, secondary_user_id)
          false -> acc
        end
      end)

    result = MapSet.union(sanbase_user_ids_mapset, user_ids_inherited_sanbase_pro)
    {:ok, MapSet.to_list(result)}
  end
end
