defmodule SanbaseWeb.Graphql.Schema.HyperliquidQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.HyperliquidBboResolver
  alias SanbaseWeb.Graphql.Complexity
  alias SanbaseWeb.Graphql.Middlewares.AccessControl

  object :hyperliquid_queries do
    @desc ~s"""
    Fetch Hyperliquid BBO (best bid / best offer) timeseries for a given slug.

    Each output row represents one interval bucket; within a bucket, bid and
    ask values are taken from the row with the largest `dt`, so every row
    reflects a single source snapshot.
    """
    field :hyperliquid_bbo_prices, list_of(:hyperliquid_bbo_point) do
      meta(access: :free)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, non_null(:interval))
      arg(:caching_params, :caching_params_input_object)

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&HyperliquidBboResolver.bbo_prices/3, ttl: 60, max_ttl_offset: 30)
    end
  end
end
