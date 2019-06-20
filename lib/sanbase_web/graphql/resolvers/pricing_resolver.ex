defmodule SanbaseWeb.Graphql.Resolvers.PricingResolver do
  alias Sanbase.Pricing.Subscription
  alias Sanbase.Auth.User

  def list_products_with_plans(_root, _args, _resolution) do
    Subscription.list_product_with_plans()
  end

  def subscribe(_root, %{card_token: card_token, plan_id: plan_id} = args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    Subscription.subscribe(current_user.id, card_token, plan_id)
  end

  def subscriptions(%User{} = user, _args, _resolution) do
    {:ok, Subscription.user_subscriptions(user)}
  end
end
