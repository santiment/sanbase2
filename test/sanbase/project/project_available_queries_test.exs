defmodule Sanbase.Project.AvailableQueriesTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers

  alias Sanbase.Model.Project.AvailableQueries

  @slug_metrics ["priceVolumeDiff", "socialGainersLosersStatus"] |> Enum.sort()
  setup_all_with_mocks([
    {Sanbase.SocialData.SocialVolume, [:passthrough],
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

    available_queries = AvailableQueries.get(project)
    assert "gasUsed" in available_queries
    assert "allExchanges" in available_queries
    assert "exchangeWallets" in available_queries
  end

  test "bitcoin has specific metrics" do
    project =
      insert(:project, %{
        slug: "bitcoin",
        github_link: "https://github.com/bitcoin"
      })

    available_queries = AvailableQueries.get(project)

    # There is no gas used for Bitcoin
    assert "gasUsed" not in available_queries
    assert "allExchanges" in available_queries
    assert "exchangeWallets" in available_queries
  end

  test "project with slug only" do
    # Override default values
    project =
      insert(:project, %{
        slug: "santiment",
        github_link: nil,
        infrastructure: nil,
        main_contract_address: nil,
        twitter_link: nil,
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

    available_queries = AvailableQueries.get(project)

    # some slug metrics
    assert Enum.all?(
             @slug_metrics,
             &Enum.member?(available_queries, &1)
           )

    # some eth addresses metrics
    assert Enum.all?(
             ["ethSpent", "ethSpentOverTime", "ethTopTransactions"],
             &Enum.member?(available_queries, &1)
           )

    # some ERC20 metrics
    assert "historicalBalance" in available_queries
  end
end
