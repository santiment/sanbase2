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

  def example do
    %{
      "source" => "Poloniex",
      "bids_1_percent_depth" => 6.377517025310313,
      "bids_30_percent_volume" => nil,
      "bids_30_percent_depth" => nil,
      "asks_0_75_percent_volume" => 323.69397143000003,
      "asks_0_75_percent_depth" => 1.4837395268415359,
      "asks_30_percent_depth" => nil,
      "asks_2_percent_depth" => 4.350476783883327,
      "bid" => 0.00455005,
      "asks_5_percent_volume" => 1028.7124032100003,
      "bids_10_percent_volume" => 1898.7281255600003,
      "asks_30_percent_volume" => nil,
      "bids_10_percent_depth" => 8.53569299297473,
      "bids_0_25_percent_volume" => 173.00153222999998,
      "asks_10_percent_volume" => nil,
      "asks_5_percent_depth" => 4.738938267011328,
      "asks_1_percent_depth" => 4.035078675155194,
      "timestamp" => 1_571_417_428_152,
      "asks_10_percent_depth" => nil,
      "bids_0_25_percent_depth" => 0.7868672411467281,
      "asks_1_percent_volume" => 878.31510571,
      "bids_1_percent_volume" => 1410.8348067900001,
      "bids_5_percent_volume" => 1772.2867537800003,
      "ask" => 0.00455979,
      "bids_0_75_percent_depth" => 3.113377417399543,
      "bids_5_percent_depth" => 7.995039456119882,
      "bids_0_5_percent_depth" => 3.0702330535995435,
      "bids_0_75_percent_volume" => 686.67829275,
      "asks_2_percent_volume" => 946.56222608,
      "asks_0_5_percent_volume" => 39.858584230000005,
      "asks_0_25_percent_volume" => 0.28495291,
      "asks_20_percent_volume" => nil,
      "bids_2_percent_volume" => 1719.6704601100002,
      "asks_20_percent_depth" => nil,
      "symbol" => "ZEC/BTC",
      "bids_0_5_percent_volume" => 677.13829275,
      "asks_0_5_percent_depth" => 0.1823476153675852,
      "bids_2_percent_depth" => 7.762576530692765,
      "asks_0_25_percent_depth" => 0.0012996121796948,
      "bids_20_percent_volume" => nil,
      "bids_20_percent_depth" => nil
    }
  end

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

  def example do
    %{
      "amount" => 2.11604737,
      "cost" => 337.7846416731,
      "price" => 159.63,
      "side" => "buy",
      "source" => "Kraken",
      "symbol" => "ETH/EUR",
      "timestamp" => 1_569_704_025_915
    }
  end

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
    |> publish_async(:exchange_trades)

    :ok
  end

  def handle_message(%{value: value, topic: "exchange_market_depth"}) do
    value
    |> Jason.decode!()
    |> Sanbase.Kafka.ExchangeMarketDepth.format_message()
    |> publish_async(:exchange_market_depth)

    :ok
  end

  defp publish_async(message, topic) do
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
