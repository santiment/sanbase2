defmodule Sanbase.ExternalServices.Coinmarketcap.PricePointTest do
  use ExUnit.Case

  alias Sanbase.ExternalServices.Coinmarketcap.PricePoint
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Model.Project

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
    project = %Project{
      ticker: "SAN"
    }

    {:ok, price_point: price_point, expectation: expectation, project: project}
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

  test "price_points_to_measurements called with one price point", %{price_point: price_point, expectation: expectation} do
    expectation = Map.replace!(expectation, :name, "TOTAL_MARKET_USD")

    assert PricePoint.price_points_to_measurements(price_point) == [expectation]
  end

  test "price_points_to_measurements called with array of price point", %{price_point: price_point, expectation: expectation} do
    price_point_new = Map.replace!(price_point, :datetime, DateTime.from_unix!(1_367_174_821_000_000_000, :nanosecond))
    expectation = Map.replace!(expectation, :name, "TOTAL_MARKET_USD")
    expectation_new = expectation
      |> Map.replace!(:timestamp, 1_367_174_821_000_000_000)
      |> Map.replace!(:name, "TOTAL_MARKET_USD")

    assert PricePoint.price_points_to_measurements([price_point, price_point_new]) == [expectation, expectation_new]
  end

  test "price_points_to_measurements called with one price point and project", %{price_point: price_point, expectation: expectation, project: project} do
    expectation_usd = Map.replace!(expectation, :name, "SAN_USD")
    expectation_btc = Map.replace!(expectation, :name, "SAN_BTC")

    assert PricePoint.price_points_to_measurements(price_point, project) == [expectation_usd, expectation_btc]
  end

  test "price_points_to_measurements called with array of price point and project", %{price_point: price_point, expectation: expectation, project: project} do
    price_point_new = Map.replace!(price_point, :datetime, DateTime.from_unix!(1_367_174_821_000_000_000, :nanosecond))
    expectation_usd = Map.replace!(expectation, :name, "SAN_USD")
    expectation_btc = Map.replace!(expectation, :name, "SAN_BTC")
    expectation_usd_new = expectation
      |> Map.replace!(:timestamp, 1_367_174_821_000_000_000)
      |> Map.replace!(:name, "SAN_USD")
    expectation_btc_new = expectation
      |> Map.replace!(:timestamp, 1_367_174_821_000_000_000)
      |> Map.replace!(:name, "SAN_BTC")

    assert PricePoint.price_points_to_measurements([price_point, price_point_new], project) ==
      [expectation_usd, expectation_btc, expectation_usd_new, expectation_btc_new]
  end
end
