defmodule SanbaseWeb.Graphql.Schema.ExchangeQueries do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.ExchangeResolver

  object :exchange_queries do
    field :last_exchange_trades, list_of(:exchange_trade) do
      arg(:exchange, non_null(:string))
      arg(:ticker_pair, non_null(:string))
      arg(:limit, non_null(:integer), default_value: 100)

      resolve(&ExchangeResolver.last_exchange_trades/3)
    end

    field :exchange_trades, list_of(:exchange_trade) do
      arg(:exchange, non_null(:string))
      arg(:ticker_pair, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string)

      resolve(&ExchangeResolver.exchange_trades/3)
    end
  end
end
