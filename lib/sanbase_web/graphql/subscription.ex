defmodule SanbaseWeb.Graphql.Subscription do
  @callback publish(map()) :: :ok

  @kafka_topic_module_map %{
    "exchange_trades" => SanbaseWeb.Graphql.Subscriptions.ExchangeTrades,
    "exchange_market_depth" => SanbaseWeb.Graphql.Subscriptions.ExchangeMarketDepth
  }

  @kafka_topics Map.keys(@kafka_topic_module_map)

  def publish(message, kafka_topic) when kafka_topic in @kafka_topics do
    module = @kafka_topic_module_map[kafka_topic]
    module.publish(message)
  end
end
