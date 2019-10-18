defmodule Sanbase.ExternalServices.Coinmarketcap.TickerFetcherTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.ExternalServices.Coinmarketcap.TickerFetcher
  alias Sanbase.Prices.Store
  alias Sanbase.Model.Project

  import Sanbase.Factory
  import Sanbase.InfluxdbHelpers

  @btc_measurement "BTC_bitcoin"
  @eth_measurement "ETH_ethereum"

  setup do
    setup_prices_influxdb()

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

  test "ticker fetcher fetches prices" do
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

  test "ticker fetcher fetches stores in multiple measurements" do
    project =
      insert(:project, %{
        ticker: "ETH",
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

    assert Store.fetch_price_points!("ETH_ethereum2", from, to) == [
             [
               DateTime.from_naive!(~N[2018-08-17 08:54:55], "Etc/UTC"),
               300.96820061,
               0.04633099381624731,
               30_511_368_440,
               1_689_698_769
             ]
           ]
  end
end
