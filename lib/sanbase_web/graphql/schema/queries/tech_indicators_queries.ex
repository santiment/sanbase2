defmodule SanbaseWeb.Graphql.Schema.TechIndicatorsQueries do
  @moduledoc ~s"""
  Queries wrapping tech-indicators API
  """
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.TechIndicatorsResolver
  alias SanbaseWeb.Graphql.Complexity

  alias SanbaseWeb.Graphql.Middlewares.AccessControl

  object :tech_indicators_queries do
    @desc ~s"""
    Fetch the price-volume difference technical indicator for a given ticker, display currency and time period.
    This indicator measures the difference in trend between price and volume,
    specifically when price goes up as volume goes down.
    """
    field :price_volume_diff, list_of(:price_volume_diff) do
      meta(access: :free)

      arg(:slug, non_null(:string))
      @desc "Currently supported currencies: USD, BTC"
      arg(:currency, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")
      arg(:size, :integer, default_value: 0)

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&TechIndicatorsResolver.price_volume_diff/3)
    end
  end
end
