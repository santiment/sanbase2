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
      |> Enum.map(fn %{selections: selections} ->
        selections
        |> Enum.map(fn %{name: name} -> name end)
      end)

    should_cache? = Enum.all?(queries, &Enum.member?(&1, @cached_queries))

    if should_cache? do
      Cache.get_or_store(
        blueprint.execution.context.query_cache_key,
        fn -> blueprint.result end
      )
    end

    conn
  end
end
