defmodule SanbaseWeb.Graphql.AbsintheBeforeSend do
  @moduledoc ~s"""
  Cache the whole result right before it is send to the client.

  The Blueprint's `result` field contains the final result as a single map.
  This result is made up of the top-level resolver and all custom resolvers.

  Caching the end result instead of each resolver separately allows to
  resolve the whole query with a single cache call - some queries could have
  thousands of custom resolver invocations.

  In order to cache a result all of the following conditions must be true:
  - All queries must be present in the `@cached_queries` list
  - The resolved value must not be an error
  - During resolving there must not be any `:nocache` returned.

  Most of the simple queries use 1 cache call and won't benefit from this approach.
  Only queries with many resolvers are included in the list of allowed queries.
  """
  alias SanbaseWeb.Graphql.Cache

  @compile inline: [has_errors?: 1]
  @cached_queries [
    "all_projects",
    "all_erc20_projects",
    "all_currency_projectsf",
    "project_by_slug",
    "projects_list_history_stats",
    "projects_list_stats"
  ]

  def before_send(conn, %Absinthe.Blueprint{} = blueprint) do
    requested_queries =
      blueprint.operations
      |> Enum.flat_map(fn %{selections: selections} ->
        selections
        |> Enum.map(fn %{name: name} -> name end)
      end)

    all_queries_cachable? =
      requested_queries
      |> Enum.all?(&Enum.member?(@cached_queries, Macro.underscore(&1)))

    has_nocache_field? = Process.get(:has_nocache_field)

    if !has_errors?(blueprint.result) && all_queries_cachable? && !has_nocache_field? do
      Cache.store(
        blueprint.execution.context.query_cache_key,
        blueprint.result
      )
    end

    conn
  end

  defp has_errors?(%{errors: _}), do: true
  defp has_errors?(_), do: false
end
