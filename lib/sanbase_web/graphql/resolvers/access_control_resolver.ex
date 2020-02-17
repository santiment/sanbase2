defmodule SanbaseWeb.Graphql.Resolvers.AccessControlResolver do
  alias Sanbase.Billing.Subscription

  def get_access_restrictions(_root, _args, %{
        context: %{product_id: product_id} = context
      }) do
    subscription = context[:auth][:subscription] || Subscription.free_subscription()

    restrictions = Sanbase.Billing.Plan.Restrictions.get(subscription, product_id)

    {:ok, restrictions}
  end

  def get_access_control(_root, _args, _resolution) do
    {:error, "The query does not have a product key in the context."}
  end
end
