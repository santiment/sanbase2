defmodule SanbaseWeb.Graphql.Schema.Subscriptions.KafkaSubscriptions do
  use Absinthe.Schema.Notation

  object :kafka_subscriptions do
    field :exchange_market_depth, :exchange_market_depth do
      arg(:source, non_null(:string))
      arg(:symbol, :string)

      config(fn
        %{source: source, symbol: symbol}, _ when not is_nil(symbol) ->
          {:ok, topic: source <> symbol}

        %{source: source}, _ ->
          {:ok, topic: source}
      end)
    end

    field :exchange_trades, :exchange_trade do
      arg(:source, :string)
      arg(:symbol, :string)

      config(fn
        %{source: source, symbol: symbol}, _ when not is_nil(symbol) ->
          {:ok, topic: source <> symbol}

        %{source: source}, _ when not is_nil(source) ->
          {:ok, topic: source}
      end)
    end
  end
end
