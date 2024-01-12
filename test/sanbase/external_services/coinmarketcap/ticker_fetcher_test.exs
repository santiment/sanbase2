defmodule Sanbase.ExternalServices.Coinmarketcap.TickerFetcherTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.ExternalServices.Coinmarketcap.TickerFetcher
  alias Sanbase.Model.LatestCoinmarketcapData
  alias Sanbase.Project

  @topic "asset_prices"

  setup do
    Sanbase.KafkaExporter.start_link(
      name: :prices_exporter,
      buffering_max_messages: 5000,
      kafka_flush_timeout: 0,
      can_send_after_interval: 0,
      topic: @topic
    )

    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{status: 200, body: File.read!(Path.join(__DIR__, "data/pro_cmc_api_2.json"))}
    end)

    :ok
  end

  test "ticker fetcher inserts the proper latest coinmarketcap data in postgres" do
    TickerFetcher.work()
    ethereum_latest_cmc = LatestCoinmarketcapData.by_coinmarketcap_id("ethereum")
    assert ethereum_latest_cmc.coinmarketcap_integer_id == 1027

    bitcoin_latest_cmc = LatestCoinmarketcapData.by_coinmarketcap_id("bitcoin")
    assert bitcoin_latest_cmc.coinmarketcap_integer_id == 1
  end

  test "ticker fetcher inserts new projects" do
    assert Project.List.projects() == []
    assert Project.List.projects_with_source("coinmarketcap") == []

    TickerFetcher.work()

    assert length(Project.List.projects()) == 2
    assert length(Project.List.projects_with_source("coinmarketcap")) == 2
  end

  test "ticker fetcher inserts new projects with correct coinmarketcap mapping" do
    TickerFetcher.work()
    projects = Project.List.projects_with_source("coinmarketcap")

    for project <- projects do
      assert project.slug == project.source_slug_mappings |> List.first() |> Map.get(:slug)
    end
  end

  test "ticker fetcher stores prices in kafka" do
    insert(:project, %{slug: "ethereum"})
    insert(:project, %{slug: "bitcoin"})

    TickerFetcher.work()
    Process.sleep(200)

    state = Sanbase.InMemoryKafka.Producer.get_state()
    %{"asset_prices" => prices} = state
    prices = Enum.map(prices, fn {k, v} -> {k, Jason.decode!(v)} end)

    expected_record1 =
      {"coinmarketcap_bitcoin_2018-08-17T08:55:37.000Z",
       Jason.decode!(
         "{\"timestamp\":1534496137,\"source\":\"coinmarketcap\",\"slug\":\"bitcoin\",\"price_usd\":6493.02288075,\"price_btc\":1.0,\"volume_usd\":4858871494,\"marketcap_usd\":111774707274}"
       )}

    expected_record2 =
      {"coinmarketcap_ethereum_2018-08-17T08:54:55.000Z",
       Jason.decode!(
         "{\"timestamp\":1534496095,\"source\":\"coinmarketcap\",\"slug\":\"ethereum\",\"price_usd\":300.96820061,\"price_btc\":0.04633099381624731,\"volume_usd\":1689698769,\"marketcap_usd\":30511368440}"
       )}

    assert expected_record1 in prices

    assert expected_record2 in prices
  end
end
