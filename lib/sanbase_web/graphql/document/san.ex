defmodule SanbaseWeb.Graphql.Document.San do
  @behaviour Absinthe.Plug.DocumentProvider

  @handled_queries [
    "allProjects",
    "allErc20Projects",
    "allCurrencyProjects",
    "eth_spent_over_time_by_erc20_projects",
    "all_projects_project_transparency",
    "userList",
    "projectBySlug"
  ]

  require Logger
  alias SanbaseWeb.Graphql.Cache

  def process(%{params: params} = request, smth) do
    case(process_params(params)) do
      {:fetch_from_cache, hash} -> cache_get(request, hash)
      _ -> {:cont, request}
    end
  end

  def process(request, _), do: {:cont, request}

  def pipeline(%{pipeline: as_configured} = options) do
    as_configured
    # |> Enum.reject(fn
    #   {{x, _}, _} ->
    #     x == Absinthe.Resolution

    #   {x, _} ->
    #     x == Absinthe.Phase.Document.Execution.Resolution

    #   _ ->
    #     false
    # end)
  end

  defp cache_get(request, hash) do
    case ConCache.get(Cache.cache_name(), hash) do
      nil ->
        {:cont, request}

      {:ok, document} ->
        {:halt, request}

      error ->
        Logger.warn(
          "Error occured getting cache entry for #{inspect(hash)}. Reason: #{inspect(error)}"
        )

        {:cont, request}
    end
  end

  defp process_params(%{
         "query" => query,
         "operationName" => operationName,
         "variables" => variables
       }) do
    hash = Cache.cache_key(query, variables: variables)
    {:fetch_from_cache, hash}
  end

  defp process_params(params) do
    params
  end
end
