defmodule Sanbase.Model.Project.AvailableMetrics do
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

  @doc ~s"""
  Return a listo of all GraphQL query names that have data for the provided
  project identified by a `slug` argument.

  In order to determine which metrics are available a list of rules is appled.
  These rules include checking for twitter link, github link, ethereum or
  bitcoin addresses, icos, presence in the list of project with social metrics,
  etc.
  """
  @spec get(Sanbase.Model.Project.t()) :: [String.t()]
  def get(%Project{} = project) do
    [
      &slug_metrics/1,
      &github_metrics/1,
      &twitter_metrics/1,
      &social_metrics/1,
      &blockchain_metrics/1,
      &database_defined_metrics/1,
      &wallets_metrics/1,
      &ico_metrics/1
    ]
    |> Enum.flat_map(fn fun -> fun.(project) end)
    |> Enum.uniq()
  end

  # Metrics can also be added from the admin dashboard
  defp database_defined_metrics(%Project{} = _project) do
    []
  end

  defp ico_metrics(%Project{} = project) do
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

  defp wallets_metrics(%Project{} = project) do
    project =
      project
      |> Sanbase.Repo.preload([:eth_addresses, :btc_addresses])

    eth_wallet_metrics =
      case project do
        %Project{eth_addresses: addresses} when addresses != [] ->
          ["ethSpent", "ethSpentOverTime", "ethTopTransactions", "ethBalance", "usdBalance"]

        _ ->
          []
      end

    btc_wallet_metrics =
      case project do
        %Project{btc_addresses: addresses} when addresses != [] ->
          ["btcBalance", "usdBalance"]

        _ ->
          []
      end

    btc_wallet_metrics ++ eth_wallet_metrics
  end

  defp slug_metrics(%Project{coinmarketcap_id: slug}) do
    case slug do
      slug when is_binary(slug) and slug != "" ->
        ["historyPrice", "ohlc", "priceVolumeDiff"]

      _ ->
        []
    end
  end

  defp github_metrics(%Project{} = project) do
    case Project.github_organization(project) do
      {:ok, _} ->
        [
          "devActivity",
          "githubActivity",
          "aveargeDevActivity",
          "averageGithubActivity"
        ]

      _ ->
        []
    end
  end

  defp twitter_metrics(%Project{twitter_link: twitter_link}) do
    case twitter_link do
      l when is_binary(l) and l != "" -> ["historyTwitterData", "twitterData"]
      _ -> []
    end
  end

  defp social_metrics(%Project{coinmarketcap_id: slug}) do
    common_social_metrics = [
      "socialGainersLosersStatus"
    ]

    case slug in social_volume_projects() do
      true -> common_social_metrics ++ ["socialVolume", "socialDominance"]
      false -> common_social_metrics
    end
  end

  @mineable_specific_metrics ["exchangeWallets", "allExchanges"]

  @ethereum_specific_metrics [
    "exchangeWallets",
    "miningPoolsDistribution",
    "dailyActiveDeposits",
    "gasUsed"
  ]

  @erc20_specific_metrics [
    "exchangeFundsFlow",
    "historicalBalance",
    "topHoldersPercentOfTotalSupply",
    "percentOfTokenSupplyOnExchanges",
    "shareOfDeposits",
    "tokenTopTransactions"
  ]

  @bitcoin_specific_metrics []

  @common_blockchain_metrics [
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

  defp blockchain_metrics(%Project{} = project) do
    is_erc20? = Project.is_erc20?(project)

    case {project, is_erc20?} do
      {%Project{coinmarketcap_id: "ethereum"}, _} ->
        @mineable_specific_metrics ++
          @ethereum_specific_metrics ++ @erc20_specific_metrics ++ @common_blockchain_metrics

      {%Project{coinmarketcap_id: "bitcoin"}, _} ->
        @mineable_specific_metrics ++ @bitcoin_specific_metrics ++ @common_blockchain_metrics

      {_, true} ->
        @erc20_specific_metrics ++ @common_blockchain_metrics

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
    |> Enum.reject(fn %{"isDeprecated" => is_deprecated} -> is_deprecated == true end)
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
    SanbaseWeb.Graphql.Cache.func(
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
