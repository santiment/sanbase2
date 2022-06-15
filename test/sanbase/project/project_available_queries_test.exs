defmodule Sanbase.Project.AvailableQueriesTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Model.Project.AvailableQueries

  @slug_metrics ["socialGainersLosersStatus"] |> Enum.sort()

  test "ethereum has specific metrics" do
    project =
      insert(:project, %{
        slug: "ethereum",
        eth_addresses: [build(:project_eth_address)],
        github_organizations: [build(:github_organization)]
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
        github_organizations: [build(:github_organization)]
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
        github_organizations: [],
        infrastructure: nil,
        contract_addresses: [],
        twitter_link: nil,
        eth_addresses: []
      })

    assert AvailableQueries.get(project) == @slug_metrics
  end

  test "project with slug, github, infrastructure, contract and eth addresses" do
    project =
      insert(:project, %{
        infrastructure: build(:infrastructure, %{code: "ETH"}),
        github_organizations: [build(:github_organization)],
        contract_addresses: [build(:contract_address)],
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
