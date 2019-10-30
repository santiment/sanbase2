defmodule Sanbase.Kafka.Topic.ExchangeTrade do
  @topic "exchange_trades"
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
