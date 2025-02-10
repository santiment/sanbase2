defmodule Sanbase.Billing.Subscription.ProPlus do
  @moduledoc false
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Product
  alias Sanbase.Billing.Subscription
  alias Sanbase.Repo
  alias Sanbase.StripeApi

  @pro_plus_plans [203, 204]
  @basic_api_plans [101, 103]
  @free_basic_api_plan 101

  def basic_api_plans, do: @basic_api_plans

  def create_free_basic_api do
    Enum.each(users_eligible_for_free_basic_plan(), fn user_id ->
      user_id
      |> free_basic_api_subscription_data()
      |> StripeApi.create_subscription()
    end)
  end

  def delete_free_basic_api do
    all_pro_plus_users = all_pro_plus_users()

    Enum.each(all_free_basic_api_subs(), fn sub ->
      if not user_has_pro_plus?(all_pro_plus_users, sub.user_id) do
        StripeApi.cancel_subscription_immediately(sub.stripe_id)
      end
    end)
  end

  def users_eligible_for_free_basic_plan do
    all_api_users = all_api_users()

    Enum.reject(all_pro_plus_users(), fn user_id ->
      user_has_api_subscription?(all_api_users, user_id)
    end)
  end

  def all_free_basic_api_subs do
    Subscription
    |> Subscription.Query.all_active_and_trialing_subscriptions_for_plans(@basic_api_plans)
    |> Repo.all()
    |> Enum.filter(fn sub ->
      {:ok, stripe_sub} = StripeApi.retrieve_subscription(sub.stripe_id)
      stripe_sub.discount && stripe_sub.discount.coupon.percent_off == 100.00
    end)
  end

  def user_has_pro_plus?(all_pro_plus_users, user_id) do
    user_id in all_pro_plus_users
  end

  def all_pro_plus_users do
    Subscription
    |> Subscription.Query.all_active_and_trialing_subscriptions_for_plans(@pro_plus_plans)
    |> Subscription.Query.select_field(:user_id)
    |> Repo.all()
    |> Enum.dedup()
  end

  def all_api_users do
    Subscription
    |> Subscription.Query.all_active_and_trialing_subscriptions()
    |> Subscription.Query.filter_product_id(Product.product_api())
    |> Subscription.Query.select_field(:user_id)
    |> Repo.all()
    |> Enum.dedup()
  end

  def user_has_api_subscription?(all_api_users, user_id) do
    user_id in all_api_users
  end

  defp free_basic_api_subscription_data(user_id) do
    plan = Plan.by_id(@free_basic_api_plan)
    user = User.by_id!(user_id)

    update_with_coupon(%{customer: user.stripe_customer_id, items: [%{plan: plan.stripe_id}]}, 100)
  end

  defp update_with_coupon(data, percent_off) when is_integer(percent_off) do
    with {:ok, coupon} <-
           StripeApi.create_coupon(%{percent_off: percent_off, duration: "forever"}) do
      Map.put(data, :coupon, coupon.id)
    end
  end
end
