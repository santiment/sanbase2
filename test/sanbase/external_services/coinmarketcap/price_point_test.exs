defmodule Sanbase.ExternalServices.Coinmarketcap.PricePointTest do
  use ExUnit.Case

  alias Sanbase.ExternalServices.Coinmarketcap.PricePoint
  alias Sanbase.Influxdb.Measurement

  setup do
    dt = 1_367_174_820_000_000_000
    price_point = %PricePoint{
      marketcap: 400,
      volume_usd: 500,
      datetime: DateTime.from_unix!(dt, :nanosecond)
    }
    expectation = %Measurement{
      timestamp: dt,
      fields: %{
        price: nil,
        volume: price_point.volume_usd,
        marketcap: price_point.marketcap
      },
      tags: [],
    }

    {:ok, price_point: price_point, expectation: expectation}
  end

  test "converting price point to measurement for BTC", %{price_point: price_point, expectation: expectation} do
    price_point = Map.replace!(price_point, :price_btc, 100)
    fields = Map.replace!(expectation.fields, :price, price_point.price_btc)
    expectation = expectation
      |> Map.replace!(:name, "SAN_BTC")
      |> Map.replace!(:fields, fields)

    assert PricePoint.convert_to_measurement(price_point, "BTC", "SAN") == expectation
  end

  test "converting price point to measurement for USD", %{price_point: price_point, expectation: expectation} do
    price_point = Map.replace!(price_point, :price_usd, 100)
    fields = Map.replace!(expectation.fields, :price, price_point.price_usd)
    expectation = expectation
      |> Map.replace!(:name, "SAN_USD")
      |> Map.replace!(:fields, fields)

    assert PricePoint.convert_to_measurement(price_point, "USD", "SAN") == expectation
  end

  test "converting price point to measurement for USD when price_usd is missing", %{price_point: price_point, expectation: expectation} do
    expectation = Map.replace!(expectation, :name, "SAN_USD")

    assert PricePoint.convert_to_measurement(price_point, "USD", "SAN") == expectation
  end
end
