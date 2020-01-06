defmodule Sanbase.ExternalServices.Coinmarketcap.WebApiTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Sanbase.InfluxdbHelpers

  alias Sanbase.ExternalServices.Coinmarketcap.WebApi
  alias Sanbase.Prices.Store

  @moduletag capture_log: true
  @total_market_measurement "TOTAL_MARKET_total-market"

  setup do
    setup_prices_influxdb()

    project =
      insert(:project, %{
        slug: "bitcoin",
        source_slug_mappings: [
          build(:source_slug_mapping, %{source: "coinmarketcap", slug: "bitcoin"})
        ]
      })

    insert(:latest_cmc_data, %{coinmarketcap_id: "bitcoin"})

    [project: project]
  end

  test "fetching the first price datetime of a token", context do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{status: 400, body: File.read!(Path.join(__DIR__, "data/btc_web_api_error.json"))}
    end)

    {:ok, first_datetime} = WebApi.first_datetime(context.project)

    assert DateTime.compare(~U[2013-04-28T18:47:21.000Z], first_datetime) == :eq
  end

  test "fetching prices of a token", context do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{
        status: 200,
        body: File.read!(Path.join(__DIR__, "data/btc_web_api_success.json"))
      }
    end)

    from_datetime = ~U[2018-01-01T23:59:01.000Z]

    WebApi.fetch_and_store_prices(context.project, from_datetime)
    state = Sanbase.InMemoryKafka.Producer.get_state()
    prices = state["asset_prices"]
    assert length(prices) > 0

    record =
      {"coinmarketcap_bitcoin_2018-01-01T23:59:20.000Z",
       "{\"marketcap_usd\":229119666553,\"price_btc\":1.0,\"price_usd\":13657.23046875,\"slug\":\"bitcoin\",\"source\":\"coinmarketcap\",\"timestamp\":1514851160,\"volume_usd\":10291150848}"}

    assert record in prices
  end

  test "fetching the first total market capitalization datetime" do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{
        status: 200,
        body: File.read!(Path.join(__DIR__, "data/total_market_web_api_error.json"))
      }
    end)

    {:ok, first_datetime} = WebApi.first_datetime("TOTAL_MARKET")
    assert first_datetime == ~U[2013-04-28 18:47:21.000Z]
  end

  test "fetching total market capitalization" do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{
        status: 200,
        body: File.read!(Path.join(__DIR__, "data/total_market_web_api_success.json"))
      }
    end)

    WebApi.fetch_and_store_prices("TOTAL_MARKET", ~U[2018-01-01 00:00:00Z])

    state = Sanbase.InMemoryKafka.Producer.get_state()
    prices = state["asset_prices"]
    assert length(prices) > 0

    record =
      {"coinmarketcap_TOTAL_MARKET_2018-01-03T00:00:00.000Z",
       "{\"marketcap_usd\":673426702336,\"price_btc\":null,\"price_usd\":null,\"slug\":\"TOTAL_MARKET\",\"source\":\"coinmarketcap\",\"timestamp\":1514937600,\"volume_usd\":43249201152}"}

    assert record in prices
  end

  test "total marketcap correctly saved to influxdb" do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{
        status: 200,
        body: File.read!(Path.join(__DIR__, "data/total_market_web_api_success.json"))
      }
    end)

    WebApi.fetch_and_store_prices("TOTAL_MARKET", ~U[2018-01-01 00:00:00Z])

    {:ok, [[_datetime, mean_volume]]} =
      Store.fetch_average_volume(
        @total_market_measurement,
        ~U[2018-01-01 00:00:00Z],
        ~U[2018-01-05 00:00:00Z]
      )

    assert mean_volume == 47_753_700_352
  end
end
