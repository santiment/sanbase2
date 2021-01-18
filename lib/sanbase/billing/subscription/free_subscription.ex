defmodule Sanbase.Billing.Subscription.FreeSubscription do
  @moduledoc """
  Free subscriptions are subscriptions present only in Sanbase but
  not synced in Stripe. They are given on some conditions.
  One example of such condition is when user has staked SAN tokens in given
  Uniswap liquidity pools.
  """

  import Ecto.Query

  alias Sanbase.Billing.Subscription
  alias Sanbase.Auth.User
  alias Sanbase.Repo

  # SAN stake  required for free subscription
  @san_stake_required_free_sub 2000
  @san_stake_free_plan Sanbase.Billing.Plan.Metadata.current_san_stake_plan()

  def create_free_subscription(user_id) do
    Subscription.create(%{
      user_id: user_id,
      plan_id: @san_stake_free_plan,
      status: "active"
    })
  end

  def remove_free_subscription(free_subscription) do
    Repo.delete(free_subscription)
  end

  # Active here is `active` and `past_due` statuses
  def user_has_active_sanbase_subscriptions?(user_id) do
    Subscription
    |> all_active_sanbase_subscriptions_query()
    |> filter_user_query(user_id)
    |> Repo.all()
    |> Enum.any?()
  end

  # Subscriptions present only in Sanbase - without stripe_id
  def all_free_subscriptions() do
    Subscription
    |> all_active_sanbase_subscriptions_query()
    |> free_subscriptions_query()
  end

  def maybe_create_free_subscription(user_id) do
    !user_has_active_sanbase_subscriptions?(user_id) &&
      User.fetch_san_staked_user(user_id) >= @san_stake_free_plan &&
      create_free_subscription(user_id)
  end

  # Create free subscription for those that don't have one and with enough SAN staked
  # Remove free subscription of those who have one and don't have enough SAN staked
  def sync_free_subscriptions_staked_users do
    maybe_create_free_subscriptions_staked_users()
    maybe_remove_free_subscriptions_staked_users()
  end

  def maybe_create_free_subscriptions_staked_users() do
    user_ids_with_enough_staked()
    |> Enum.each(fn user_id ->
      unless user_has_active_sanbase_subscriptions?(user_id) do
        create_free_subscription(user_id)
      end
    end)
  end

  def maybe_remove_free_subscriptions_staked_users() do
    free_subscriptions = all_free_subscriptions()
    user_ids_with_enough_staked = user_ids_with_enough_staked()

    free_subscriptions
    |> Enum.each(fn %{user_id: user_id} = free_subscription ->
      unless user_id in user_ids_with_enough_staked do
        remove_free_subscription(free_subscription)
      end
    end)
  end

  defp all_active_sanbase_subscriptions_query(query) do
    from(q in query,
      where:
        q.plan_id == ^@san_stake_free_plan and
          q.status in ["active", "past_due"]
    )
  end

  defp free_subscriptions_query(query) do
    from(q in query, where: is_nil(q.stripe_id))
  end

  defp filter_user_query(query, user_id) do
    from(q in query, where: q.user_id == ^user_id)
  end

  defp user_ids_with_enough_staked() do
    User.fetch_san_staked_users()
    |> Enum.filter(&(&1.san_staked >= @san_stake_required_free_sub))
    |> Enum.map(& &1.user_id)
  end
end
