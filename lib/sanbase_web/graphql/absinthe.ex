defmodule SanbaseWeb.Graphql.Absinthe do
  alias SanbaseWeb.Graphql.Cache

  @cached_queries [
    "allProjects",
    "allErc20Projects",
    "allCurrencyProjects",
    "projectBySlug",
    "projectsListHistoryStats",
    "projectsListStats"
  ]

  def before_send(conn, %Absinthe.Blueprint{} = blueprint) do
    queries =
      blueprint.operations
      |> Enum.flat_map(fn %{selections: selections} ->
        selections
        |> Enum.map(fn %{name: name} -> name end)
      end)

    all_queries_cachable? = Enum.all?(queries, &Enum.member?(@cached_queries, &1))
    has_nocache_field? = Process.get(:has_nocache_field)

    if all_queries_cachable? && !has_nocache_field? do
      Cache.store(
        blueprint.execution.context.query_cache_key,
        blueprint.result
      )
    end

    conn
  end
end
