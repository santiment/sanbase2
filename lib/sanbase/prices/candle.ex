defmodule Sanbase.Prices.Candle do
  # Represents a price candle with a given open, close, high and low price
  # during a given time period. Also stores the trading volume for that period
  defstruct [:datetime, :open, :close, :high, :low, :volume]

  alias Sanbase.Prices.Point
  alias Sanbase.Prices.Candle

  def from_points([head | points], interval) when is_list(points) do
    current_candle = %Candle{
      datetime: head.datetime,
      open: head.price,
      close: head.price,
      high: head.price,
      low: head.price,
      volume: head.volume
    }

    points
    |> Enum.reduce([current_candle], &reduce_point_into_candles/2)
  end

  defp reduce_point_into_candles(%Point{datetime: datetime, price: price}, [current_candle | candles]) do

  end
end
