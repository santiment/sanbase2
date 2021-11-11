defmodule Sanbase.Billing.Subscription.ProPlus do
  alias Sanbase.Billing.{Subscription, Plan, Product}
  alias Sanbase.StripeApi
  alias Sanbase.Repo
  alias Sanbase.Accounts.User

  @pro_plus_plans [203, 204]
  @basic_api_plans [101, 103]
  @free_basic_api_plan 101

  def create_free_basic_api do
    users_eligible_for_free_basic_plan()
    |> Enum.each(fn user_id ->
      free_basic_api_subscription_data(user_id)
      |> StripeApi.create_subscription()
    end)
  end

  def delete_free_basic_api do
    all_free_basic_api_subs()
    |> Enum.each(fn sub ->
      if not user_has_pro_plus?(sub.user_id) do
        StripeApi.delete_subscription(sub.stripe_id)
      end
    end)
  end

  def users_eligible_for_free_basic_plan do
    all_pro_plus_subs()
    |> Enum.reject(fn sub ->
      user_has_api_subscription?(sub.user_id)
    end)
    |> Enum.map(& &1.user_id)
  end

  def all_pro_plus_subs do
    Subscription
    |> Subscription.Query.all_active_and_trialing_subscriptions_for_plans(@pro_plus_plans)
    |> Repo.all()
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

  def user_has_pro_plus?(user_id) do
    Subscription
    |> Subscription.Query.all_active_and_trialing_subscriptions_for_plans(@pro_plus_plans)
    |> Subscription.Query.filter_user(user_id)
    |> Repo.all()
    |> Enum.any?()
  end

  def user_has_api_subscription?(user_id) do
    Subscription
    |> Subscription.Query.all_active_and_trialing_subscriptions()
    |> Subscription.Query.filter_user(user_id)
    |> Subscription.Query.product_id(Product.product_api())
    |> Repo.all()
    |> Enum.any?()
  end

  defp free_basic_api_subscription_data(user_id) do
    plan = Plan.by_id(@free_basic_api_plan)
    user = User.by_id!(user_id)

    %{
      customer: user.stripe_customer_id,
      items: [%{plan: plan.stripe_id}]
    }
    |> update_with_coupon(100)
  end

  defp update_with_coupon(data, percent_off) when is_integer(percent_off) do
    with {:ok, coupon} <-
           StripeApi.create_coupon(%{percent_off: percent_off, duration: "forever"}) do
      Map.put(data, :coupon, coupon.id)
    end
  end
end
