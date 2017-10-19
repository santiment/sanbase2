defmodule Sanbase.Prices.CandleTest do
  use ExUnit.Case, async: true

  alias Sanbase.Prices.Candle
  alias Sanbase.Prices.Point

  test "calculating candles from no points" do
    assert Candle.from_points([], 2) == []
  end

  test "calculating candles from a single point" do
    point = %Point{datetime: 1, price: 1, volume: 1}
    assert Candle.from_points([point], 2) == [%Candle{datetime: 1, open: 1, high: 1, low: 1, close: 1, volume: 1}]
  end

  test "calculating candles from points" do
    points = [
      %Point{datetime: 1, price: 1, volume: 1},
      %Point{datetime: 2, price: 2, volume: 2},
      %Point{datetime: 3, price: 3, volume: 3},
      %Point{datetime: 4, price: 2, volume: 2},
      %Point{datetime: 5, price: 1, volume: 1},
    ]

    [c1, c2, c3] = Candle.from_points(points, 2)

    assert c1 == %Candle{datetime: 1, open: 1, high: 2, low: 1, close: 2, volume: 3}
    assert c2 == %Candle{datetime: 3, open: 3, high: 3, low: 2, close: 2, volume: 5}
    assert c3 == %Candle{datetime: 5, open: 1, high: 1, low: 1, close: 1, volume: 1}
  end
end
