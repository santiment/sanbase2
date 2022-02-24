defmodule Sanbase.Billing.Subscription.LiquiditySubscription do
  @moduledoc """
  Liquidity subscriptions are free subscriptions given when user has staked enough SAN tokens in given
  Uniswap liquidity pools. They are present only in Sanbase but not synced in Stripe.
  """

  alias Sanbase.Billing.{Subscription, Product}
  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  # SAN stake required for free subscription. We advertise 3000 SAN
  # but require >= 2000 due to possible fluctuations of staked amount in pools.
  @san_stake_required_liquidity_sub 2000
  @san_stake_free_plan Sanbase.Billing.Plan.Metadata.current_san_stake_plan()

  @spec create_liquidity_subscription(non_neg_integer()) ::
          {:ok, %Subscription{}} | {:error, any()}
  def create_liquidity_subscription(user_id) do
    Subscription.create(
      %{
        user_id: user_id,
        plan_id: @san_stake_free_plan,
        status: "active",
        current_period_end: Timex.shift(Timex.now(), days: 30)
      },
      event_args: %{type: :liquidity_subscription}
    )
  end

  def remove_liquidity_subscription(liquidity_subscription) do
    Subscription.delete(
      liquidity_subscription,
      event_args: %{type: :liquidity_subscription}
    )
  end

  @doc """
  Subscriptions present only in Sanbase but not in Stripe
  They don't have `stripe_id`
  """
  @spec list_liquidity_subscriptions() :: list(%Subscription{})
  def list_liquidity_subscriptions() do
    Subscription
    |> Subscription.Query.all_active_subscriptions_for_plan(@san_stake_free_plan)
    |> Subscription.Query.liquidity_subscriptions()
    |> Repo.all()
  end

  @doc """
  User has any active subscriptions.
  Active here is `active` and `past_due` statuses, but not `trialing`
  """
  @spec user_has_active_sanbase_subscriptions?(non_neg_integer()) :: boolean()
  def user_has_active_sanbase_subscriptions?(user_id) do
    Subscription
    |> Subscription.Query.all_active_subscriptions_for_product(Product.product_sanbase())
    |> Subscription.Query.filter_user(user_id)
    |> Repo.all()
    |> Enum.any?()
  end

  @doc """
  User doesn't have active Sanbase subscriptions and have enough SAN staked
  """
  @spec eligible_for_liquidity_subscription?(non_neg_integer()) :: boolean()
  def eligible_for_liquidity_subscription?(user_id) do
    !user_has_active_sanbase_subscriptions?(user_id) and
      User.fetch_uniswap_san_staked_user(user_id) >= @san_stake_required_liquidity_sub
  end

  @doc """
  Create free liquidity subscription for those that don't have one and with enough SAN staked
  Remove free liquidity subscription of those who have one and don't have enough SAN staked
  """
  def sync_liquidity_subscriptions_staked_users do
    maybe_create_liquidity_subscriptions_staked_users()
    maybe_remove_liquidity_subscriptions_staked_users()
  end

  @doc """
  Create free liquidity subscription for those that don't have one and with enough SAN staked
  """
  def maybe_create_liquidity_subscriptions_staked_users() do
    user_ids_with_enough_staked()
    |> Enum.each(fn user_id ->
      if not user_has_active_sanbase_subscriptions?(user_id) do
        create_liquidity_subscription(user_id)
      end
    end)
  end

  @doc """
  Remove free liquidity subscription of those who have one and don't have enough SAN staked
  """
  def maybe_remove_liquidity_subscriptions_staked_users() do
    liquidity_subscriptions = list_liquidity_subscriptions()
    user_ids_with_enough_staked = user_ids_with_enough_staked()

    liquidity_subscriptions
    |> Enum.each(fn %{user_id: user_id} = liquidity_subscription ->
      if user_id not in user_ids_with_enough_staked do
        remove_liquidity_subscription(liquidity_subscription)
      end
    end)
  end

  # Helpers

  defp user_ids_with_enough_staked() do
    User.fetch_all_uniswap_staked_users()
    |> Enum.filter(&(&1.san_staked >= @san_stake_required_liquidity_sub))
    |> Enum.map(& &1.user_id)
  end
end
