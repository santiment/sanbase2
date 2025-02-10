defmodule SanbaseWeb.Graphql.Resolvers.MarketResolver do
  @moduledoc false
  import Sanbase.Utils.ErrorHandling,
    only: [maybe_handle_graphql_error: 2, handle_graphql_error: 3]

  require Logger

  def market_exchanges(_root, _args, _resolution) do
    maybe_handle_graphql_error(Sanbase.Market.list_exchanges(), fn error ->
      handle_graphql_error(
        "Market Exchanges",
        nil,
        error
      )
    end)
  end
end
