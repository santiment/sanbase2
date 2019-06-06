defmodule Sanbase.Project.AvailableMetricsTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory

  alias Sanbase.Model.Project.AvailableMetrics

  @slug_metrics [
    "historyPrice",
    "ohlc",
    "priceVolumeDiff",
    "socialGainersLosersStatus",
    "socialVolume",
    "socialDominance"
  ]

  setup_with_mocks([
    {Sanbase.TechIndicators, [],
     [social_volume_projects: fn -> {:ok, ["bitcoin", "ethereum", "santiment"]} end]}
  ]) do
    []
  end

  test "btcBalance present only when there are btc addresses" do
    project_with_btc =
      insert(:project, %{
        coinmarketcap_id: rand_str(),
        btc_addresses: [build(:project_btc_address)]
      })

    project_without_btc =
      insert(:project, %{
        coinmarketcap_id: rand_str(),
        btc_addresses: []
      })

    assert "btcBalance" in AvailableMetrics.get(project_with_btc)
    assert "btcBalance" not in AvailableMetrics.get(project_without_btc)
  end

  test "ethBalance present only when there are eth addresses" do
    project_with_eth =
      insert(:project, %{
        coinmarketcap_id: rand_str(),
        eth_addresses: [build(:project_eth_address)]
      })

    project_without_eth =
      insert(:project, %{
        coinmarketcap_id: rand_str(),
        eth_addresses: []
      })

    assert "ethBalance" in AvailableMetrics.get(project_with_eth)
    assert "ethBalance" not in AvailableMetrics.get(project_without_eth)
  end

  test "ethereum has specific metrics" do
    project =
      insert(:project, %{
        coinmarketcap_id: "ethereum",
        github_link: "https://github.com/ethereum",
        eth_addresses: [build(:project_eth_address)]
      })

    available_metrics = AvailableMetrics.get(project)
    assert "gasUsed" in available_metrics
    assert "allExchanges" in available_metrics
    assert "exchangeWallets" in available_metrics
  end

  test "bitcoin has specific metrics" do
    project =
      insert(:project, %{
        coinmarketcap_id: "bitcoin",
        github_link: "https://github.com/bitcoin"
      })

    available_metrics = AvailableMetrics.get(project)

    # There is no gas used for Bitcoin
    assert "gasUsed" not in available_metrics
    assert "allExchanges" in available_metrics
    assert "exchangeWallets" in available_metrics
  end

  test "project with slug only" do
    # Override default values
    project =
      insert(:project, %{
        coinmarketcap_id: "santiment",
        github_link: nil,
        infrastructure: nil,
        main_contract_address: nil,
        eth_addresses: []
      })

    assert AvailableMetrics.get(project) == @slug_metrics
  end

  test "project with slug, github, infrastructure, contract and eth addresses" do
    project =
      insert(:project, %{
        coinmarketcap_id: "santiment",
        github_link: "https://github.com/santiment",
        infrastructure: build(:infrastructure, %{code: "ETH"}),
        main_contract_address: "0x" <> rand_hex_str(),
        eth_addresses: [build(:project_eth_address)]
      })

    available_metrics = AvailableMetrics.get(project)

    # some github metrics
    assert Enum.all?(
             ["githubActivity", "aveargeDevActivity", "averageGithubActivity"],
             &Enum.member?(available_metrics, &1)
           )

    # some slug metrics
    assert Enum.all?(
             @slug_metrics,
             &Enum.member?(available_metrics, &1)
           )

    # some eth addresses metrics
    assert Enum.all?(
             ["ethSpent", "ethSpentOverTime", "ethTopTransactions", "ethBalance"],
             &Enum.member?(available_metrics, &1)
           )

    # some ERC20 metrics
    assert Enum.all?(
             [
               "dailyActiveAddresses",
               "transactionVolume",
               "tokenVelocity",
               "exchangeFundsFlow",
               "historicalBalance"
             ],
             &Enum.member?(available_metrics, &1)
           )
  end
end
