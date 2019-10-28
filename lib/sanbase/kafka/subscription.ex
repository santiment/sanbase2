defmodule Sanbase.Kafka.Subscription do
  @kafka_topic_graphql_subscription_map %{
    "exchange_trades" => :exchange_trades,
    "exchange_market_depth" => :exchange_market_depth
  }

  def publish(message, kafka_topic) do
    Absinthe.Subscription.publish(
      SanbaseWeb.Endpoint,
      message,
      Keyword.new([
        {@kafka_topic_graphql_subscription_map[kafka_topic], message.source <> message.symbol}
      ])
    )

    Absinthe.Subscription.publish(
      SanbaseWeb.Endpoint,
      message,
      Keyword.new([{@kafka_topic_graphql_subscription_map[kafka_topic], message.source}])
    )
  end
end
