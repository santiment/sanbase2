defmodule Sanbase.ExternalServices.Coinmarketcap.WebApiTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.ExternalServices.Coinmarketcap.WebApi

  @moduletag capture_log: true

  setup do
    project =
      insert(:project, %{
        slug: "bitcoin",
        source_slug_mappings: [
          build(:source_slug_mapping, %{source: "coinmarketcap", slug: "bitcoin"})
        ]
      })

    Sanbase.InMemoryKafka.Producer.clear_state()

    insert(:latest_cmc_data, %{coinmarketcap_id: "bitcoin"})

    [project: project]
  end

  test "filter out huge volumes", context do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{
        status: 200,
        body: File.read!(Path.join(__DIR__, "data/btc_web_api_success_huge_volume.json"))
      }
    end)

    WebApi.fetch_and_store_prices(context.project, ~U[2018-01-01T23:59:01.000Z])
    prices = Sanbase.InMemoryKafka.Producer.get_state() |> Map.get("asset_prices")

    filtered_record =
      {"coinmarketcap_bitcoin_2018-01-01T23:59:20.000Z",
       "{\"marketcap_usd\":229119666553,\"price_btc\":1.0,\"price_usd\":13657.23046875,\"slug\":\"bitcoin\",\"source\":\"coinmarketcap\",\"timestamp\":1514851160,\"volume_usd\":null}"}

    ok_record =
      {"coinmarketcap_bitcoin_2018-01-02T23:59:22.000Z",
       "{\"marketcap_usd\":251377940171,\"price_btc\":1.0,\"price_usd\":14982.1015625,\"slug\":\"bitcoin\",\"source\":\"coinmarketcap\",\"timestamp\":1514937562,\"volume_usd\":16846582784}"}

    assert filtered_record in prices
    assert ok_record in prices
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

  test "fetching the first datetime with error msg" do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{
        status: 200,
        body: File.read!(Path.join(__DIR__, "data/total_market_web_api_error.json"))
      }
    end)

    {:ok, first_datetime} = WebApi.first_datetime("TOTAL_MARKET")
    assert first_datetime == ~U[2013-04-28 18:47:21.000Z]
  end

  test "fetching the first datetime with success msg", context do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{
        status: 200,
        body: File.read!(Path.join(__DIR__, "data/first_datetime_api_success.json"))
      }
    end)

    {:ok, first_datetime} = WebApi.first_datetime(context.project)
    assert first_datetime == ~U[2019-04-29 00:00:00Z]
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
end
