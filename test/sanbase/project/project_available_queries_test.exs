defmodule Sanbase.Project.AvailableQueriesTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory

  alias Sanbase.Model.Project.AvailableQueries

  @slug_metrics [
    "historyPrice",
    "ohlc",
    "priceVolumeDiff",
    "socialGainersLosersStatus",
    "socialVolume",
    "socialDominance"
  ]

  setup_with_mocks([
    {Sanbase.TechIndicators, [:passthrough],
     [social_volume_projects: fn -> {:ok, ["bitcoin", "ethereum", "santiment"]} end]}
  ]) do
    []
  end

  test "ethereum has specific metrics" do
    project =
      insert(:project, %{
        slug: "ethereum",
        github_link: "https://github.com/ethereum",
        eth_addresses: [build(:project_eth_address)]
      })

    available_metrics = AvailableQueries.get(project)
    assert "gasUsed" in available_metrics
    assert "allExchanges" in available_metrics
    assert "exchangeWallets" in available_metrics
  end

  test "bitcoin has specific metrics" do
    project =
      insert(:project, %{
        slug: "bitcoin",
        github_link: "https://github.com/bitcoin"
      })

    available_metrics = AvailableQueries.get(project)

    # There is no gas used for Bitcoin
    assert "gasUsed" not in available_metrics
    assert "allExchanges" in available_metrics
    assert "exchangeWallets" in available_metrics
  end

  test "project with slug only" do
    # Override default values
    project =
      insert(:project, %{
        slug: "santiment",
        github_link: nil,
        infrastructure: nil,
        main_contract_address: nil,
        eth_addresses: [],
        github_organizations: []
      })

    assert AvailableQueries.get(project) == @slug_metrics
  end

  test "project with slug, github, infrastructure, contract and eth addresses" do
    project =
      insert(:project, %{
        infrastructure: build(:infrastructure, %{code: "ETH"}),
        main_contract_address: "0x" <> rand_hex_str(),
        eth_addresses: [build(:project_eth_address)]
      })

    available_metrics = AvailableQueries.get(project)

    # some github metrics
    assert Enum.all?(
             ["githubActivity", "devActivity"],
             &Enum.member?(available_metrics, &1)
           )

    # some slug metrics
    assert Enum.all?(
             @slug_metrics,
             &Enum.member?(available_metrics, &1)
           )

    # some eth addresses metrics
    assert Enum.all?(
             ["ethSpentOverTime"],
             &Enum.member?(available_metrics, &1)
           )

    # some ERC20 metrics
    assert Enum.all?(
             ["exchangeFundsFlow", "historicalBalance"],
             &Enum.member?(available_metrics, &1)
           )
  end
end
