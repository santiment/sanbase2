defmodule SanbaseWeb.Graphql.Schema.PricingQueries do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.PricingResolver

  alias SanbaseWeb.Graphql.Middlewares.{
    JWTAuth
  }

  import_types(SanbaseWeb.Graphql.Schema.PricingTypes)

  object :pricing_queries do
    @desc ~s"""
    List available products with corresponding subscription plans.
    """
    field :products_with_plans, list_of(:product) do
      resolve(&PricingResolver.products_with_plans/3)
    end
  end

  object :pricing_mutations do
    @desc ~s"""
    Subscribe logged in user to a chosen plan using card_token retuned by Stripe on filling
    card information.
    """
    field :subscribe, :subscription_plan do
      arg(:card_token, non_null(:string))
      arg(:plan_id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&PricingResolver.subscribe/3)
    end

    @desc ~s"""
    Upgrade/Downgrade a subscription to another plan using existing card information.
    """
    field :update_subscription, :subscription_plan do
      arg(:subscription_id, non_null(:integer))
      arg(:plan_id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&PricingResolver.update_subscription/3)
    end

    @desc ~s"""
    Request cancelling a subscription. Subscription won't be deactivated immediately but
    will be active until the current subscription period ends.
    """
    field :cancel_subscription, :subscription_cancellation do
      arg(:subscription_id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&PricingResolver.cancel_subscription/3)
    end
  end
end
