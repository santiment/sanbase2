defmodule Sanbase.Kafka.Subscription do
  @spec publish(map, String.t()) :: :ok
  def publish(message, kafka_topic) do
    SanbaseWeb.Graphql.Subscription.publish(message, kafka_topic)
  end
end
