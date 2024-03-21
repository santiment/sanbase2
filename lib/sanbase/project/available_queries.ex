defmodule Sanbase.Project.AvailableQueries do
  @moduledoc ~s"""
  Module for determining what metrics are available for a given project
  """

  alias Sanbase.Project
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
    |> Enum.map(fn query ->
      query
      |> Macro.underscore()
      # credo:disable-for-next-line
      |> String.to_atom()
    end)
  end

  @doc ~s"""
  Return a list of all GraphQL query names that have data for the provided
  project identified by a `slug` argument.

  In order to determine which metrics are available a list of rules is appled.
  These rules include checking for twitter link, github link, ethereum or
  bitcoin addresses, icos, presence in the list of project with social metrics,
  etc.
  """
  @spec get(Sanbase.Project.t()) :: [String.t()]
  def get(%Project{} = project) do
    project = project |> Sanbase.Repo.preload([:eth_addresses, :infrastructure])

    [
      &historical_balance_queries/1,
      &holders_queries/1,
      &blockchain_metric_queries/1,
      &wallets_queries/1,
      &get_metric_queries/1
    ]
    |> Enum.flat_map(fn fun -> fun.(project) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp get_metric_queries(%Project{slug: slug}) do
    case Sanbase.Metric.available_slugs() do
      {:ok, list} -> if slug in list, do: ["getMetric"], else: []
      _ -> []
    end
  end

  defp wallets_queries(%Project{} = project) do
    case project do
      %Project{eth_addresses: addresses} when addresses != [] ->
        ["ethSpent", "ethSpentOverTime", "ethTopTransactions"]

      _ ->
        []
    end
  end

  def historical_balance_queries(%Project{} = project) do
    case Project.infrastructure_real_code(project) do
      {:ok, infr} ->
        if infr in Sanbase.Clickhouse.HistoricalBalance.supported_infrastructures(),
          do: ["historicalBalance"],
          else: []

      _ ->
        []
    end
  end

  def holders_queries(%Project{} = project) do
    case Project.infrastructure_real_code(project) do
      {:ok, infr} ->
        if infr in Sanbase.Clickhouse.TopHolders.MetricAdapter.supported_infrastructures(),
          do: ["topHoldersPercentOfTotalSupply"],
          else: []

      _ ->
        []
    end
  end

  @mineable_specific_queries ["exchangeWallets", "allExchanges"]
  @ethereum_specific_queries ["gasUsed"]
  @bitcoin_specific_queries []

  defp blockchain_metric_queries(%Project{} = project) do
    case {project, Project.is_erc20?(project)} do
      {%Project{slug: "ethereum"}, _} ->
        @mineable_specific_queries ++
          @ethereum_specific_queries

      {%Project{slug: "bitcoin"}, _} ->
        @mineable_specific_queries ++ @bitcoin_specific_queries

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
end
