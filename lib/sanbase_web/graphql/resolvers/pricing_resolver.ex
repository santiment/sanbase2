defmodule SanbaseWeb.Graphql.Resolvers.PricingResolver do
  alias Sanbase.Pricing.{Subscription, Plan}
  alias Sanbase.Auth.User

  def products_with_plans(_root, _args, _resolution) do
    Plan.product_with_plans()
  end

  def subscribe(_root, %{card_token: card_token, plan_id: plan_id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    Subscription.subscribe(current_user.id, card_token, plan_id)
  end

  def update_subscription(_root, %{subscription_id: subscription_id, plan_id: plan_id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    Subscription.update_subscription(current_user.id, subscription_id, plan_id)
  end

  def cancel_subscription(_root, %{subscription_id: subscription_id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    Subscription.cancel_subscription(current_user.id, subscription_id)
  end

  def subscriptions(%User{} = user, _args, _resolution) do
    {:ok, Subscription.user_subscriptions(user)}
  end
end
