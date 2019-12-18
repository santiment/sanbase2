defmodule Sanbase.ExternalServices.Coinmarketcap.TickerFetcherTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.ExternalServices.Coinmarketcap.TickerFetcher
  alias Sanbase.Prices.Store
  alias Sanbase.Model.Project

  import Sanbase.Factory
  import Sanbase.InfluxdbHelpers
  import Sanbase.TestHelpers

  @btc_measurement "BTC_bitcoin"
  @eth_measurement "ETH_ethereum"

  @topic "asset_prices"

  setup do
    setup_prices_influxdb()
    clear_kafka_state()

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

  test "ticker fetcher stores prices in influxdb" do
    TickerFetcher.work()

    from = DateTime.from_naive!(~N[2018-08-17 08:35:00], "Etc/UTC")
    to = DateTime.from_naive!(~N[2018-08-17 10:40:00], "Etc/UTC")

    # Test bitcoin is in influx
    assert Store.fetch_price_points!(@btc_measurement, from, to) == [
             [
               DateTime.from_naive!(~N[2018-08-17 08:55:37], "Etc/UTC"),
               6493.02288075,
               1,
               111_774_707_274,
               4_858_871_494
             ]
           ]

    # Test Ethereum is in influx
    assert Store.fetch_price_points!(@eth_measurement, from, to) == [
             [
               DateTime.from_naive!(~N[2018-08-17 08:54:55], "Etc/UTC"),
               300.96820061,
               0.04633099381624731,
               30_511_368_440,
               1_689_698_769
             ]
           ]
  end

  test "ticker fetcher stores prices in kafka" do
    state = Sanbase.InMemoryKafka.Producer.get_state()
    assert state == %{}

    TickerFetcher.work()
    Process.sleep(200)

    state = Sanbase.InMemoryKafka.Producer.get_state()
    %{"asset_prices" => prices} = state

    assert length(prices) == 2

    keys = prices |> Enum.map(&elem(&1, 0))

    assert "coinmarketcap_bitcoin_2018-08-17T08:55:37.000Z" in keys
    assert "coinmarketcap_ethereum_2018-08-17T08:54:55.000Z" in keys
    assert state["asset_prices"] == prices_json_in_kafka()
  end

  test "ticker fetcher fetches stores in multiple measurements" do
    insert(:project, %{
      ticker: "ETH2",
      slug: "ethereum2",
      source_slug_mappings: [
        build(:source_slug_mapping, %{source: "coinmarketcap", slug: "ethereum"})
      ]
    })

    TickerFetcher.work()

    from = DateTime.from_naive!(~N[2018-08-17 08:35:00], "Etc/UTC")
    to = DateTime.from_naive!(~N[2018-08-17 10:40:00], "Etc/UTC")

    # Test bitcoin is in influx
    assert Store.fetch_price_points!(@btc_measurement, from, to) == [
             [
               DateTime.from_naive!(~N[2018-08-17 08:55:37], "Etc/UTC"),
               6493.02288075,
               1,
               111_774_707_274,
               4_858_871_494
             ]
           ]

    # Test Ethereum is in influx
    assert Store.fetch_price_points!(@eth_measurement, from, to) == [
             [
               DateTime.from_naive!(~N[2018-08-17 08:54:55], "Etc/UTC"),
               300.96820061,
               0.04633099381624731,
               30_511_368_440,
               1_689_698_769
             ]
           ]

    assert Store.fetch_price_points!("ETH2_ethereum2", from, to) == [
             [
               DateTime.from_naive!(~N[2018-08-17 08:54:55], "Etc/UTC"),
               300.96820061,
               0.04633099381624731,
               30_511_368_440,
               1_689_698_769
             ]
           ]
  end

  defp prices_json_in_kafka do
    [
      {"coinmarketcap_bitcoin_2018-08-17T08:55:37.000Z",
       "{\"marketcap_usd\":111774707274,\"price_btc\":1.0,\"price_usd\":6493.02288075,\"slug\":\"bitcoin\",\"source\":\"coinmarketcap\",\"timestamp\":1534496137,\"volume_usd\":4858871494}"},
      {"coinmarketcap_ethereum_2018-08-17T08:54:55.000Z",
       "{\"marketcap_usd\":30511368440,\"price_btc\":0.04633099381624731,\"price_usd\":300.96820061,\"slug\":\"ethereum\",\"source\":\"coinmarketcap\",\"timestamp\":1534496095,\"volume_usd\":1689698769}"}
    ]
  end
end
