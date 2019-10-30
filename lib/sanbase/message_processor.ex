defmodule Sanbase.Kafka.MessageProcessor do
  def handle_messages(messages) do
    Enum.each(messages, &handle_message/1)
  end

  def handle_message(%{value: value, topic: "exchange_trades"}) do
    value
    |> Jason.decode!()
    |> Sanbase.Kafka.Topic.ExchangeTrade.format_message()
    |> Sanbase.Kafka.Subscription.publish("exchange_trades")
  end

  def handle_message(%{value: value, topic: "exchange_market_depth"}) do
    value
    |> Jason.decode!()
    |> Sanbase.Kafka.Topic.ExchangeMarketDepth.format_message()
    |> Sanbase.Kafka.Subscription.publish("exchange_market_depth")
  end
end
