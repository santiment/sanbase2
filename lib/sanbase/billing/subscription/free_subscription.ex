defmodule Sanbase.Billing.Subscription.FreeSubscription do
  @moduledoc """
  Free subscriptions are subscriptions present only in Sanbase but
  not synced in Stripe. They are given on some conditions.
  An example of such condition is when user has staked SAN tokens in given
  Uniswap liquidity pools.
  """

  alias Sanbase.Billing.Subscription
  alias Sanbase.Auth.User
  alias Sanbase.Repo

  # SAN stake required for free subscription. We advertise 3000 SAN
  # but require >= 2000 due to possible fluctuations of staked amount in pools.
  @san_stake_required_free_sub 2000
  @san_stake_free_plan Sanbase.Billing.Plan.Metadata.current_san_stake_plan()

  @spec create_free_subscription(non_neg_integer()) :: {:ok, %Subscription{}} | {:error, any()}
  def create_free_subscription(user_id) do
    Subscription.create(%{
      user_id: user_id,
      plan_id: @san_stake_free_plan,
      status: "active",
      current_period_end: Timex.shift(Timex.now(), days: 30)
    })
  end

  def remove_free_subscription(free_subscription) do
    Repo.delete(free_subscription)
  end

  @doc """
  Subscriptions present only in Sanbase but not in Stripe
  They don't have `stripe_id`
  """
  @spec list_free_subscriptions() :: list(%Subscription{})
  def list_free_subscriptions() do
    Subscription
    |> Subscription.Query.all_active_subscriptions_for_plan_query(@san_stake_free_plan)
    |> Subscription.Query.free_subscriptions_query()
    |> Repo.all()
  end

  @doc """
  User has any active subscriptions.
  Active here is `active` and `past_due` statuses, but not `trialing`
  """
  @spec user_has_active_sanbase_subscriptions?(non_neg_integer()) :: boolean()
  def user_has_active_sanbase_subscriptions?(user_id) do
    Subscription
    |> Subscription.Query.all_active_subscriptions_for_plan_query(@san_stake_free_plan)
    |> Subscription.Query.filter_user_query(user_id)
    |> Repo.all()
    |> Enum.any?()
  end

  @doc """
  User doesn't have active Sanbase subscriptions and have enough SAN staked
  """
  @spec eligible_for_free_subscription?(non_neg_integer()) :: boolean()
  def eligible_for_free_subscription?(user_id) do
    !user_has_active_sanbase_subscriptions?(user_id) and
      User.fetch_uniswap_san_staked_user(user_id) >= @san_stake_required_free_sub
  end

  @doc """
  Create free subscription for those that don't have one and with enough SAN staked
  Remove free subscription of those who have one and don't have enough SAN staked
  """
  def sync_free_subscriptions_staked_users do
    maybe_create_free_subscriptions_staked_users()
    maybe_remove_free_subscriptions_staked_users()
  end

  @doc """
  Create free subscription for those that don't have one and with enough SAN staked
  """
  def maybe_create_free_subscriptions_staked_users() do
    user_ids_with_enough_staked()
    |> Enum.each(fn user_id ->
      unless user_has_active_sanbase_subscriptions?(user_id) do
        create_free_subscription(user_id)
      end
    end)
  end

  @doc """
  Remove free subscription of those who have one and don't have enough SAN staked
  """
  def maybe_remove_free_subscriptions_staked_users() do
    free_subscriptions = list_free_subscriptions()
    user_ids_with_enough_staked = user_ids_with_enough_staked()

    free_subscriptions
    |> Enum.each(fn %{user_id: user_id} = free_subscription ->
      unless user_id in user_ids_with_enough_staked do
        remove_free_subscription(free_subscription)
      end
    end)
  end

  # Helpers

  defp user_ids_with_enough_staked() do
    User.fetch_all_uniswap_staked_users()
    |> Enum.filter(&(&1.san_staked >= @san_stake_required_free_sub))
    |> Enum.map(& &1.user_id)
  end
end
