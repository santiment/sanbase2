defmodule SanbaseWeb.Graphql.Schema.PriceQueries do
  @moduledoc false
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Complexity
  alias SanbaseWeb.Graphql.Middlewares.AccessControl
  alias SanbaseWeb.Graphql.Resolvers.PriceResolver

  object :price_queries do
    @desc "Fetch price history for a given slug and time interval."
    field :history_price, list_of(:price_point) do
      meta(access: :free)

      arg(:slug, :string)
      arg(:ticker, :string, deprecate: "Use slug instead of ticker")
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&PriceResolver.history_price/3)
    end

    @desc ~s"""
    Fetch open, high, low close price values for a given slug and every time interval between from-to.
    """

    field :ohlc, list_of(:ohlc) do
      meta(access: :free)

      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&PriceResolver.ohlc/3)
    end
  end
end
