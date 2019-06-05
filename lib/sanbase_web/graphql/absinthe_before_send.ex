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

  @compile inline: [cache_result: 2]
  @cached_queries [
    "all_projects",
    "all_erc20_projects",
    "all_currency_projects",
    "project_by_slug",
    "projects_list_history_stats",
    "projects_list_stats"
  ]

  def before_send(conn, %Absinthe.Blueprint{result: %{errors: _}}), do: conn

  def before_send(conn, %Absinthe.Blueprint{} = blueprint) do
    # Do not cache in case of:
    # -`:nocache` returend from a resolver
    # - result is taken from the cache and should not be stored again. Storing
    # it again `touch`es it and the TTL timer is restarted. This can lead
    # to infinite storing the same value if there are enough requests

    should_cache? = !Process.get(:do_not_cache_query)
    cache_result(should_cache?, blueprint)

    conn
    |> maybe_update_session(blueprint.execution.context)
  end

  defp cache_result(true, blueprint) do
    requested_queries =
      blueprint.operations
      |> Enum.flat_map(fn %{selections: selections} ->
        selections
        |> Enum.map(fn %{name: name} -> name end)
      end)

    all_queries_cachable? =
      requested_queries
      |> Enum.all?(&Enum.member?(@cached_queries, Macro.underscore(&1)))

    if all_queries_cachable? do
      Cache.store(
        blueprint.execution.context.query_cache_key,
        blueprint.result
      )
    end
  end

  defp cache_result(_, _), do: :ok

  defp maybe_update_session(conn, %{auth_token: auth_token}) do
    Plug.Conn.put_session(conn, :auth_token, auth_token)
  end

  defp maybe_update_session(conn, _), do: conn
end
