defmodule Sanbase.Kafka.ExchangeMarketDepth do
  defstruct [
    :source,
    :symbol,
    :timestamp,
    :ask,
    :asks025_percent_depth,
    :asks025_percent_volume,
    :asks05_percent_depth,
    :asks05_percent_volume,
    :asks075_percent_depth,
    :asks075_percent_volume,
    :asks10_percent_depth,
    :asks10_percent_volume,
    :asks1_percent_depth,
    :asks1_percent_volume,
    :asks20_percent_depth,
    :asks20_percent_volume,
    :asks2_percent_depth,
    :asks2_percent_volume,
    :asks30_percent_depth,
    :asks30_percent_volume,
    :asks5_percent_depth,
    :asks5_percent_volume,
    :bid,
    :bids025_percent_depth,
    :bids025_percent_volume,
    :bids05_percent_depth,
    :bids05_percent_volume,
    :bids075_percent_depth,
    :bids075_percent_volume,
    :bids10_percent_depth,
    :bids10_percent_volume,
    :bids1_percent_depth,
    :bids1_percent_volume,
    :bids20_percent_depth,
    :bids20_percent_volume,
    :bids2_percent_depth,
    :bids2_percent_volume,
    :bids30_percent_depth,
    :bids30_percent_volume,
    :bids5_percent_depth,
    :bids5_percent_volume
  ]

  def format_message(message_map) do
    message_map
    |> Enum.map(fn {k, v} -> {Regex.replace(~r/_(\d+)/, k, "\\1"), v} end)
    |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
    |> Enum.into(%{})
    |> format_timestamp()
  end

  defp format_timestamp(%{timestamp: timestamp} = exchange_market_depth) do
    %{exchange_market_depth | timestamp: DateTime.from_unix!(floor(timestamp), :millisecond)}
  end
end

defmodule Sanbase.Kafka.ExchangeTrade do
  defstruct [:source, :symbol, :timestamp, :amount, :cost, :price, :side]

  def format_message(message_map) do
    message_map
    |> Enum.map(fn {k, v} -> {Regex.replace(~r/_(\d+)/, k, "\\1"), v} end)
    |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
    |> Enum.into(%{})
    |> format_timestamp()
    |> format_side()
  end

  defp format_timestamp(%{timestamp: timestamp} = exchange_trade) do
    %{exchange_trade | timestamp: DateTime.from_unix!(floor(timestamp), :millisecond)}
  end

  defp format_side(%{side: side} = exchange_trade) do
    %{exchange_trade | side: String.to_existing_atom(side)}
  end
end

defmodule Sanbase.Kafka.Subscription do
  def publish(message, topic) do
    Absinthe.Subscription.publish(
      SanbaseWeb.Endpoint,
      message,
      Keyword.new([{topic, "*"}])
    )

    Absinthe.Subscription.publish(
      SanbaseWeb.Endpoint,
      message,
      Keyword.new([{topic, message.source <> message.symbol}])
    )

    Absinthe.Subscription.publish(
      SanbaseWeb.Endpoint,
      message,
      Keyword.new([{topic, message.source}])
    )
  end
end

defmodule Sanbase.Kafka.MessageProcessor do
  def handle_messages(messages) do
    for message <- messages do
      handle_message(message)
    end

    # Important!
    :ok
  end

  def handle_message(%{value: value, topic: "exchange_trades"}) do
    value
    |> Jason.decode!()
    |> Sanbase.Kafka.ExchangeTrade.format_message()
    |> Sanbase.Kafka.Subscription.publish(:exchange_trades)

    :ok
  end

  def handle_message(%{value: value, topic: "exchange_market_depth"}) do
    value
    |> Jason.decode!()
    |> Sanbase.Kafka.ExchangeMarketDepth.format_message()
    |> Sanbase.Kafka.Subscription.publish(:exchange_market_depth)

    :ok
  end
end
