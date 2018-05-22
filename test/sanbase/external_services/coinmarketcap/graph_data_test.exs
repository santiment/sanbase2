defmodule Sanbase.ExternalServices.Coinmarketcap.GraphDataTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.ExternalServices.Coinmarketcap.GraphData2, as: GraphData
  alias Sanbase.ExternalServices.Coinmarketcap.PricePoint2, as: PricePoint
  alias Sanbase.Prices.Store

  @total_market_measurement "TOTAL_MARKET_total-market"

  test "fetching the first price datetime of a token" do
    Tesla.Mock.mock(fn %{
                         method: :get,
                         url: "https://graphs2.coinmarketcap.com/currencies/santiment/"
                       } ->
      %Tesla.Env{status: 200, body: File.read!(Path.join(__DIR__, "btc_graph_data.json"))}
    end)

    assert GraphData.fetch_first_datetime("santiment") ==
             DateTime.from_unix!(1_507_991_665_000, :millisecond)
  end

  test "fetching prices of a token" do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{status: 200, body: File.read!(Path.join(__DIR__, "btc_graph_data.json"))}
    end)

    from_datetime = DateTime.from_unix!(1_507_991_665_000, :millisecond)
    to_datetime = DateTime.from_unix!(1_508_078_065_000, :millisecond)

    GraphData.fetch_price_stream("santiment", from_datetime, to_datetime)
    |> Stream.flat_map(fn x -> x end)
    |> Stream.take(1)
    |> Enum.map(fn %PricePoint{datetime: datetime, price_usd: price_usd} ->
      assert datetime == from_datetime
      assert price_usd == 5704.29
    end)
  end

  test "fetching the first total market capitalization datetime" do
    Tesla.Mock.mock(fn %{
                         method: :get,
                         url: "https://graphs2.coinmarketcap.com/global/marketcap-total/"
                       } ->
      %Tesla.Env{
        status: 200,
        body: File.read!(Path.join(__DIR__, "coinmarketcap_total_graph_data.json"))
      }
    end)

    assert GraphData.fetch_first_datetime(@total_market_measurement) ==
             DateTime.from_unix!(1_367_174_820_000, :millisecond)
  end

  test "fetching total market capitalization" do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{
        status: 200,
        body: File.read!(Path.join(__DIR__, "coinmarketcap_total_graph_data.json"))
      }
    end)

    from_datetime = DateTime.from_unix!(1_367_174_820_000, :millisecond)
    to_datetime = DateTime.from_unix!(1_386_355_620_000, :millisecond)

    GraphData.fetch_marketcap_total_stream(from_datetime, to_datetime)
    |> Stream.flat_map(fn x -> x end)
    |> Stream.take(1)
    |> Enum.map(fn %PricePoint{
                     datetime: datetime,
                     marketcap_usd: marketcap,
                     volume_usd: volume_usd
                   } ->
      assert datetime == from_datetime
      assert marketcap == 1_599_410_000
      assert volume_usd == 0
    end)
  end

  test "total marketcap correctly saved to influxdb" do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{
        status: 200,
        body: File.read!(Path.join(__DIR__, "coinmarketcap_total_graph_data.json"))
      }
    end)

    Store.create_db()
    measurement_name = "TOTAL_MARKET_total-market"
    Store.drop_measurement(measurement_name)

    # The HTTP GET request is mocked, this interval here does not play a role.
    # Put one day before now so we will have only one day range and won't make many HTTP queries
    GraphData.fetch_and_store_marketcap_total(Timex.shift(Timex.now(), days: -1))

    from = DateTime.from_unix!(0)
    to = DateTime.utc_now()

    {:ok, [[_datetime, mean_volume]]} =
      Store.fetch_mean_volume(@total_market_measurement, from, to)

    assert mean_volume == 2_513_748_896.5741253
  end
end
