defmodule Sanbase.Billing.Subscription.LiquiditySubscription do
  @moduledoc """
  Liquidity subscriptions are free subscriptions given when user has staked enough SAN tokens in given
  Uniswap liquidity pools. They are present only in Sanbase but not synced in Stripe.
  """

  alias Sanbase.Billing.Subscription
  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  # SAN stake required for free subscription. We advertise 3000 SAN
  # but require >= 2000 due to possible fluctuations of staked amount in pools.
  @san_stake_required_liquidity_sub 2000
  @san_stake_required_liquidity_sub_v3 2999
  @san_stake_free_plan Sanbase.Billing.Plan.Metadata.current_san_stake_plan()

  @spec create_liquidity_subscription(non_neg_integer()) ::
          {:ok, %Subscription{}} | {:error, any()}
  def create_liquidity_subscription(user_id) do
    Subscription.create(
      %{
        user_id: user_id,
        plan_id: @san_stake_free_plan,
        status: "active",
        current_period_end: Timex.shift(Timex.now(), days: 30),
        type: :liquidity
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
  """
  @spec list_liquidity_subscriptions() :: list(%Subscription{})
  def list_liquidity_subscriptions() do
    Subscription
    |> Subscription.Query.all_active_subscriptions_for_plan(@san_stake_free_plan)
    |> Subscription.Query.liquidity_subscriptions()
    |> Repo.all()
  end

  @doc """
  User doesn't have active Sanbase subscriptions and have enough SAN staked
  """
  @spec eligible_for_liquidity_subscription?(non_neg_integer()) :: boolean()
  def eligible_for_liquidity_subscription?(user_id) do
    not Subscription.user_has_active_sanbase_subscriptions?(user_id) and
      (user_staked_in_uniswap_v2(user_id) or user_staked_in_uniswap_v3(user_id))
  end

  def user_staked_in_uniswap_v2(user_id) do
    User.UniswapStaking.fetch_uniswap_san_staked_user(user_id) >=
      @san_stake_required_liquidity_sub
  end

  def user_staked_in_uniswap_v3(user_id) do
    addresses = Sanbase.Accounts.EthAccount.all_by_user(user_id) |> Enum.map(& &1.address)

    addresses
    |> Enum.any?(fn address ->
      Sanbase.SmartContracts.UniswapV3.get_deposited_san_tokens(address) >=
        @san_stake_required_liquidity_sub_v3
    end)
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
      if not Subscription.user_has_active_sanbase_subscriptions?(user_id) do
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
    User.UniswapStaking.fetch_all_uniswap_staked_users()
    |> Enum.filter(&(&1.san_staked >= @san_stake_required_liquidity_sub))
    |> Enum.map(& &1.user_id)
  end
end
