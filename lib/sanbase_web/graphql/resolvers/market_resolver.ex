defmodule SanbaseWeb.Graphql.Resolvers.MarketResolver do
  require Logger

  import Sanbase.Utils.ErrorHandling,
    only: [maybe_handle_graphql_error: 2, handle_graphql_error: 3]

  def market_exchanges(_root, _args, _resolution) do
    Sanbase.Market.list_exchanges()
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(
        "Market Exchanges",
        nil,
        error
      )
    end)
  end
end
