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
        body: File.read!(Path.join(__DIR__, "data/btc_web_api_success_huge_volume2.json"))
      }
    end)

    :ok = WebApi.fetch_and_store_prices(context.project, ~U[2023-07-19 00:00:00Z])
    prices = Sanbase.InMemoryKafka.Producer.get_state() |> Map.get("asset_prices")

    filtered_record =
      {"coinmarketcap_bitcoin_2023-07-19T00:00:05Z",
       "{\"marketcap_usd\":580312507941,\"price_btc\":1.0,\"price_usd\":29862.047207949952,\"slug\":\"bitcoin\",\"source\":\"coinmarketcap\",\"timestamp\":1689724805,\"volume_usd\":null}"}

    ok_record =
      {"coinmarketcap_bitcoin_2023-07-19T00:00:00Z",
       "{\"marketcap_usd\":580312507941,\"price_btc\":1.0,\"price_usd\":29862.047207949952,\"slug\":\"bitcoin\",\"source\":\"coinmarketcap\",\"timestamp\":1689724800,\"volume_usd\":13140495959}"}

    assert filtered_record in prices
    assert ok_record in prices
  end

  test "fetching prices of a token", context do
    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{
        status: 200,
        body: File.read!(Path.join(__DIR__, "data/btc_web_api_success2.json"))
      }
    end)

    from_datetime = ~U[2023-07-19 00:00:00Z]

    :ok = WebApi.fetch_and_store_prices(context.project, from_datetime)
    state = Sanbase.InMemoryKafka.Producer.get_state()
    prices = state["asset_prices"]
    assert length(prices) > 0

    record =
      {"coinmarketcap_bitcoin_2023-07-19T00:00:00Z",
       "{\"marketcap_usd\":580312507941,\"price_btc\":1.0,\"price_usd\":29862.047207949952,\"slug\":\"bitcoin\",\"source\":\"coinmarketcap\",\"timestamp\":1689724800,\"volume_usd\":13140495959}"}

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

    :ok = WebApi.fetch_and_store_prices("TOTAL_MARKET", ~U[2018-01-01 00:00:00Z])

    state = Sanbase.InMemoryKafka.Producer.get_state()
    prices = state["asset_prices"]
    assert length(prices) > 0

    assert {"coinmarketcap_TOTAL_MARKET_2023-08-21T12:35:00.000Z",
            "{\"marketcap_usd\":1053345319615,\"price_btc\":null,\"price_usd\":null,\"slug\":\"TOTAL_MARKET\",\"source\":\"coinmarketcap\",\"timestamp\":1692621300,\"volume_usd\":24975771713}"} in prices

    assert {"coinmarketcap_TOTAL_MARKET_2023-08-21T12:35:00.000Z",
            "{\"marketcap_usd\":1053345319615,\"price_btc\":null,\"price_usd\":null,\"slug\":\"TOTAL_MARKET\",\"source\":\"coinmarketcap\",\"timestamp\":1692621300,\"volume_usd\":24975771713}"} in prices
  end
end
