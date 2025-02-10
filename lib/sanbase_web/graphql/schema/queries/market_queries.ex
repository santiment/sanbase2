defmodule SanbaseWeb.Graphql.Schema.MarketQueries do
  @moduledoc false
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.MarketResolver

  object :market_queries do
    field :get_market_exchanges, list_of(:market_exchange) do
      meta(access: :free)

      cache_resolve(&MarketResolver.market_exchanges/3)
    end
  end
end
