defmodule Sanbase.ExternalServices.Coinmarketcap.GraphDataTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Sanbase.InfluxdbHelpers

  alias Sanbase.ExternalServices.Coinmarketcap.{GraphData, PricePoint}
  alias Sanbase.Prices.Store
  alias Sanbase.Model.Project

  @total_market_measurement "TOTAL_MARKET_total-market"

  # setup do
  #   setup_prices_influxdb()
  #   :ok
  # end

  test "fetching the first price datetime of a token" do
    Tesla.Mock.mock(fn %{
                         method: :get,
                         url: "https://graphs2.coinmarketcap.com/currencies/santiment/"
                       } ->
      %Tesla.Env{status: 200, body: File.read!(Path.join(__DIR__, "data/btc_graph_data.json"))}
    end)

    project =
      insert(:project, %{
        slug: "santiment",
        source_slug_mappings: [
          build(:source_slug_mapping, %{source: "coinmarketcap", slug: "santiment"})
        ]
      })

    assert GraphData.fetch_first_datetime(project) ==
             DateTime.from_unix!(1_507_991_665_000, :millisecond)
  end

  test "fetching prices of a token" do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{status: 200, body: File.read!(Path.join(__DIR__, "data/btc_graph_data.json"))}
    end)

    from_datetime = DateTime.from_unix!(1_507_991_665_000, :millisecond)
    to_datetime = DateTime.from_unix!(1_508_078_065_000, :millisecond)

    GraphData.fetch_price_stream("bitcoin", from_datetime, to_datetime)
    |> Enum.map(fn {stream, interval} -> {stream |> Enum.map(& &1), interval} end)
    |> Enum.take(1)
    |> Enum.map(fn {[%PricePoint{datetime: datetime, price_usd: price_usd} | _], _interval} ->
      assert datetime == from_datetime
      assert price_usd == 5704.29
    end)
  end

  test "fetching and exporting prices into a kafka topic" do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{status: 200, body: File.read!(Path.join(__DIR__, "data/btc_graph_data.json"))}
    end)

    from_datetime = DateTime.from_unix!(1_507_991_665_000, :millisecond)
    to_datetime = DateTime.from_unix!(1_508_078_065_000, :millisecond)

    setup_prices_influxdb()
    insert(:project, slug: "bitcoin")
    result = GraphData.fetch_and_store_prices(Project.by_slug("bitcoin"), from_datetime)
    Process.sleep(100)
    state = Sanbase.InMemoryKafka.Producer.get_state()
    Sanbase.InMemoryKafka.Producer.clear_state()

    topic = Sanbase.Kafka.Exporter.Prices.topic()

    assert hd(state[topic]) ==
             {"coinmarketcap_bitcoin_1507991665000000000",
              "{\"marketcap_usd\":94819417917,\"price_btc\":1.0,\"price_usd\":5704.29,\"slug\":\"bitcoin\",\"source\":\"coinmarketcap\",\"timestamp\":1507991665000000000,\"volume_usd\":1946510000}"}
  end

  test "fetching the first total market capitalization datetime" do
    Tesla.Mock.mock(fn %{
                         method: :get,
                         url: "https://graphs2.coinmarketcap.com/global/marketcap-total/"
                       } ->
      %Tesla.Env{
        status: 200,
        body: File.read!(Path.join(__DIR__, "data/coinmarketcap_total_graph_data.json"))
      }
    end)

    assert GraphData.fetch_first_datetime(@total_market_measurement) ==
             DateTime.from_unix!(1_367_174_820_000, :millisecond)
  end

  test "fetching total market capitalization" do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{
        status: 200,
        body: File.read!(Path.join(__DIR__, "data/coinmarketcap_total_graph_data.json"))
      }
    end)

    from_datetime = DateTime.from_unix!(1_367_174_820_000, :millisecond)
    to_datetime = DateTime.from_unix!(1_386_355_620_000, :millisecond)

    GraphData.fetch_marketcap_total_stream(from_datetime, to_datetime)
    |> Enum.map(fn {stream, interval} -> {stream |> Enum.map(& &1), interval} end)
    |> Enum.take(1)
    |> Enum.map(fn {[
                      %PricePoint{
                        datetime: datetime,
                        marketcap_usd: marketcap_usd,
                        volume_usd: volume_usd
                      }
                      | _
                    ], _interval} ->
      assert datetime == from_datetime
      assert marketcap_usd == 1_599_410_000
      assert volume_usd == 0
    end)
  end

  test "fetching total market capitalization and exporting to kafka" do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{
        status: 200,
        body: File.read!(Path.join(__DIR__, "data/coinmarketcap_total_graph_data.json"))
      }
    end)

    from_datetime = DateTime.from_unix!(1_367_174_820_000, :millisecond)
    to_datetime = DateTime.from_unix!(1_386_355_620_000, :millisecond)

    setup_prices_influxdb()
    GraphData.fetch_and_store_marketcap_total(from_datetime)
    Process.sleep(100)
    state = Sanbase.InMemoryKafka.Producer.get_state()
    Sanbase.InMemoryKafka.Producer.clear_state()

    topic = Sanbase.Kafka.Exporter.Prices.topic()

    assert List.last(state[topic]) ==
             {"coinmarketcap_TOTAL_MARKET_1522676820000000000",
              "{\"marketcap_usd\":2.63492e11,\"price_btc\":null,\"price_usd\":null,\"slug\":\"TOTAL_MARKET\",\"source\":\"coinmarketcap\",\"timestamp\":1522676820000000000,\"volume_usd\":1.21335e10}"}
  end

  test "total marketcap correctly saved to influxdb" do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{
        status: 200,
        body: File.read!(Path.join(__DIR__, "data/coinmarketcap_total_graph_data.json"))
      }
    end)

    setup_prices_influxdb()

    # The HTTP GET request is mocked, this interval here does not play a role.
    # Put one day before now so we will have only one day range and won't make many HTTP queries
    GraphData.fetch_and_store_marketcap_total(Timex.shift(Timex.now(), days: -1))

    from = DateTime.from_unix!(0)
    to = DateTime.utc_now()

    {:ok, [[_datetime, mean_volume]]} =
      Store.fetch_average_volume(@total_market_measurement, from, to)

    assert mean_volume == 2_513_748_896.5741253
  end
end
