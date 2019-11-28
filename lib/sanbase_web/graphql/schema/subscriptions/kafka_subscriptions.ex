defmodule SanbaseWeb.Graphql.Schema.Subscriptions.KafkaSubscriptions do
  use Absinthe.Schema.Notation

  object :kafka_subscriptions do
    field :exchange_market_depth, :exchange_market_depth do
      arg(:exchange, non_null(:string))
      arg(:ticker_pair, :string)

      config(fn
        %{exchange: exchange, ticker_pair: ticker_pair}, _ when not is_nil(ticker_pair) ->
          {:ok, topic: exchange <> ticker_pair}

        %{exchange: exchange}, _ ->
          {:ok, topic: exchange}
      end)
    end

    field :exchange_trades, :exchange_trade do
      arg(:exchange, :string)
      arg(:ticker_pair, :string)

      config(fn
        %{exchange: exchange, ticker_pair: ticker_pair}, _ when not is_nil(ticker_pair) ->
          {:ok, topic: exchange <> ticker_pair}

        %{exchange: exchange}, _ when not is_nil(exchange) ->
          {:ok, topic: exchange}
      end)
    end
  end
end
