defmodule Sanbase.Prices.Candle do
  # Represents a price candle with a given open, close, high and low price
  # during a given time period. Also stores the trading volume for that period
  defstruct [:datetime, :open, :close, :high, :low, :volume]

  alias Sanbase.Prices.Point
  alias Sanbase.Prices.Candle

  def from_points([], _), do: []

  def from_points([head | points], interval) when is_list(points) do
    current_candle = create_candle_from_point(head)

    points
    |> Enum.reduce([current_candle], fn point, acc ->
      reduce_point_into_candles(point, acc, interval)
    end)
    |> Enum.reverse
  end

  defp reduce_point_into_candles(%Point{datetime: datetime, price: price, volume: volume} = point, [current_candle | rest_candles] = candles, interval) do
    cond do
      datetime < current_candle.datetime + interval ->
        current_candle = %{
          current_candle |
          close: price,
          high: max(current_candle.high, price),
          low: min(current_candle.low, price),
          volume: current_candle.volume + volume
        }

        [current_candle | rest_candles]
      true ->
        new_candle = create_candle_from_point(point)
        [new_candle | candles]
    end
  end

  defp create_candle_from_point(%Point{datetime: datetime, price: price, volume: volume}) do
    %Candle{
      datetime: datetime,
      open: price,
      close: price,
      high: price,
      low: price,
      volume: volume
    }
  end
end
