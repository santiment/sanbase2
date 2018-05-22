defmodule Sanbase.ExternalServices.Coinmarketcap.PricePointTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.ExternalServices.Coinmarketcap.PricePoint2, as: PricePoint
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Model.Project

  @total_market_measurement "TOTAL_MARKET_total-market"
  setup do
    ts =
      DateTime.from_naive!(~N[2018-05-13 21:45:00], "Etc/UTC")
      |> DateTime.to_unix(:nanoseconds)

    price_point = %PricePoint{
      price_btc: nil,
      price_usd: nil,
      marketcap_usd: 400,
      volume_usd: 500,
      datetime: DateTime.from_unix!(ts, :nanosecond)
    }

    project = %Project{
      ticker: "SAN",
      coinmarketcap_id: "santiment"
    }

    expectation = %Measurement{
      timestamp: ts,
      fields: %{
        price_usd: nil,
        price_btc: nil,
        volume_usd: price_point.volume_usd,
        marketcap_usd: price_point.marketcap_usd
      },
      tags: [],
      name: Measurement.name_from(project)
    }

    %{
      price_point: price_point,
      expectation: expectation,
      project: project
    }
  end

  test "converting price point to measurement with BTC price", %{
    price_point: price_point,
    expectation: expectation,
    project: project
  } do
    price_point = Map.replace!(price_point, :price_btc, 100)
    fields = Map.replace!(expectation.fields, :price_btc, price_point.price_btc)

    expectation =
      expectation
      |> Map.replace!(:fields, fields)

    assert PricePoint.convert_to_measurement(price_point, Measurement.name_from(project)) ==
             expectation
  end

  test "converting price point to measurement with USD price", %{
    price_point: price_point,
    expectation: expectation,
    project: project
  } do
    price_point = Map.replace!(price_point, :price_usd, 100)
    fields = Map.replace!(expectation.fields, :price_usd, price_point.price_usd)

    expectation =
      expectation
      |> Map.replace!(:fields, fields)

    assert PricePoint.convert_to_measurement(price_point, Measurement.name_from(project)) ==
             expectation
  end

  test "price_points_to_measurements called with one price point", %{
    price_point: price_point,
    expectation: expectation
  } do
    expectation = Map.replace!(expectation, :name, @total_market_measurement)

    assert PricePoint.price_points_to_measurements(price_point, @total_market_measurement) == [
             expectation
           ]
  end

  test "price_points_to_measurements called with array of price point", %{
    price_point: price_point,
    expectation: expectation
  } do
    price_point_new =
      Map.replace!(
        price_point,
        :datetime,
        DateTime.from_unix!(1_367_174_821_000_000_000, :nanosecond)
      )

    expectation = Map.replace!(expectation, :name, @total_market_measurement)

    expectation_new =
      expectation
      |> Map.replace!(:timestamp, 1_367_174_821_000_000_000)
      |> Map.replace!(:name, @total_market_measurement)

    assert PricePoint.price_points_to_measurements(
             [price_point, price_point_new],
             @total_market_measurement
           ) == [
             expectation,
             expectation_new
           ]
  end

  test "price_points_to_measurements called with array of price point and project", %{
    price_point: price_point,
    expectation: expectation,
    project: project
  } do
    price_point_new =
      Map.replace!(
        price_point,
        :datetime,
        DateTime.from_unix!(1_367_174_821_000_000_000, :nanosecond)
      )

    expectation_new =
      expectation
      |> Map.replace!(:timestamp, 1_367_174_821_000_000_000)

    assert PricePoint.price_points_to_measurements([price_point, price_point_new], project) ==
             [expectation, expectation_new]
  end
end
