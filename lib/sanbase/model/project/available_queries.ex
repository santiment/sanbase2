defmodule Sanbase.Model.Project.AvailableQueries do
  @moduledoc ~s"""
  Module for determining what metrics are available for a given project
  """

  alias Sanbase.Model.Project
  require SanbaseWeb.Graphql.Schema

  @doc ~s"""
  Return a list of all GraphQL query names that have an argument `slug`
  """
  @spec all :: [String.t()]
  def all() do
    project_queries()
  end

  @spec all_atom_names() :: [atom()]
  def all_atom_names() do
    project_queries()
    |> Enum.map(&(&1 |> Macro.underscore() |> String.to_atom()))
  end

  @doc ~s"""
  Return a list of all GraphQL query names that have data for the provided
  project identified by a `slug` argument.

  In order to determine which metrics are available a list of rules is appled.
  These rules include checking for twitter link, github link, ethereum or
  bitcoin addresses, icos, presence in the list of project with social metrics,
  etc.
  """
  @spec get(Sanbase.Model.Project.t()) :: [String.t()]
  def get(%Project{} = project) do
    [
      &slug_queries/1,
      &github_queries/1,
      &twitter_queries/1,
      &social_queries/1,
      &blockchain_queries/1,
      &database_defined_queries/1,
      &wallets_queries/1,
      &ico_queries/1,
      &get_metric_queries/1
    ]
    |> Enum.flat_map(fn fun -> fun.(project) end)
    |> Enum.uniq()
  end

  # Metrics can also be added from the admin dashboard
  defp database_defined_queries(%Project{} = _project) do
    []
  end

  defp get_metric_queries(%Project{slug: slug}) do
    case Sanbase.Metric.available_slugs() do
      {:ok, list} ->
        if slug in list, do: ["getMetric"], else: []

      _ ->
        []
    end
  end

  defp ico_queries(%Project{} = project) do
    project
    |> Sanbase.Repo.preload([:icos])
    |> case do
      %Project{icos: icos} when icos != [] ->
        [
          "icos",
          "icoPrice",
          "initialIco",
          "fundsRaisedUsdIcoEndPrice",
          "fundsRaisedEthIcoEndPrice",
          "fundsRaisedBtcIcoEndPrice"
        ]

      _ ->
        []
    end
  end

  defp wallets_queries(%Project{} = project) do
    project =
      project
      |> Sanbase.Repo.preload([:eth_addresses, :btc_addresses])

    eth_wallet_queries =
      case project do
        %Project{eth_addresses: addresses} when addresses != [] ->
          ["ethSpent", "ethSpentOverTime", "ethTopTransactions", "ethBalance", "usdBalance"]

        _ ->
          []
      end

    btc_wallet_queries =
      case project do
        %Project{btc_addresses: addresses} when addresses != [] ->
          ["btcBalance", "usdBalance"]

        _ ->
          []
      end

    btc_wallet_queries ++ eth_wallet_queries
  end

  defp slug_queries(%Project{slug: slug}) do
    case slug do
      slug when is_binary(slug) and slug != "" ->
        ["historyPrice", "ohlc", "priceVolumeDiff"]

      _ ->
        []
    end
  end

  defp github_queries(%Project{} = project) do
    case Project.github_organizations(project) do
      {:ok, orgs} when is_list(orgs) and orgs != [] ->
        [
          "devActivity",
          "githubActivity",
          "averageDevActivity",
          "averageGithubActivity"
        ]

      _ ->
        []
    end
  end

  defp twitter_queries(%Project{twitter_link: twitter_link}) do
    case twitter_link do
      l when is_binary(l) and l != "" -> ["historyTwitterData", "twitterData"]
      _ -> []
    end
  end

  defp social_queries(%Project{slug: slug}) do
    common_social_queries = [
      "socialGainersLosersStatus"
    ]

    case slug in social_volume_projects() do
      true -> common_social_queries ++ ["socialVolume", "socialDominance"]
      false -> common_social_queries
    end
  end

  @mineable_specific_queries ["exchangeWallets", "allExchanges"]

  @ethereum_specific_queries [
    "exchangeWallets",
    "miningPoolsDistribution",
    "dailyActiveDeposits",
    "gasUsed"
  ]

  @erc20_specific_queries [
    "exchangeFundsFlow",
    "historicalBalance",
    "topHoldersPercentOfTotalSupply",
    "percentOfTokenSupplyOnExchanges",
    "shareOfDeposits",
    "tokenTopTransactions"
  ]

  @bitcoin_specific_queries []

  @common_blockchain_queries [
    "realizedValue",
    "networkGrowth",
    "mvrvRatio",
    "dailyActiveAddresses",
    "tokenAgeConsumed",
    "burnRate",
    "averageTokenAgeConsumedInDays",
    "tokenVelocity",
    "nvtRatio",
    "transactionVolume",
    "tokenCirculation"
  ]

  defp blockchain_queries(%Project{} = project) do
    is_erc20? = Project.is_erc20?(project)

    case {project, is_erc20?} do
      {%Project{slug: "ethereum"}, _} ->
        @mineable_specific_queries ++
          @ethereum_specific_queries ++ @erc20_specific_queries ++ @common_blockchain_queries

      {%Project{slug: "bitcoin"}, _} ->
        @mineable_specific_queries ++ @bitcoin_specific_queries ++ @common_blockchain_queries

      {_, true} ->
        @erc20_specific_queries ++ @common_blockchain_queries

      _ ->
        []
    end
  end

  defp project_queries() do
    {:ok, result} = Absinthe.run(available_queries_query(), SanbaseWeb.Graphql.Schema, [])
    %{data: %{"__schema" => %{"queryType" => %{"fields" => fields}}}} = result

    fields
    |> Enum.filter(fn %{"args" => args} ->
      Enum.any?(args, fn elem -> elem == %{"name" => "slug"} end)
    end)
    |> Enum.reject(& &1["isDeprecated"])
    |> Enum.map(& &1["name"])
  end

  defp available_queries_query() do
    """
    query availableQueries {
      __schema {
        queryType {
          fields {
            isDeprecated
            name
            args{
              name
            }
          }
        }
      }
    }
    """
  end

  # Fetch and cache the social volume projects for 30 minutes
  defp social_volume_projects() do
    SanbaseWeb.Graphql.Cache.wrap(
      fn ->
        {:ok, projects} = Sanbase.TechIndicators.social_volume_projects()
        projects
      end,
      :social_volume_projects_list,
      %{},
      ttl: 1800
    ).()
  end
end
