defmodule SanbaseWeb.Graphql.Schema.PricingQueries do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.PricingResolver

  alias SanbaseWeb.Graphql.Middlewares.{
    JWTAuth
  }

  import_types(SanbaseWeb.Graphql.Schema.PricingTypes)

  object :pricing_queries do
    @desc ~s"""
    List availbale products with corresponding subscription plans.
    """
    field :list_products_with_plans, list_of(:product) do
      resolve(&PricingResolver.list_products_with_plans/3)
    end
  end

  object :pricing_mutations do
    field :subscribe, :plan_subscription do
      arg(:card_token, non_null(:string))
      arg(:plan_id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&PricingResolver.subscribe/3)
    end
  end
end
