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

  @compile :inline_list_funcs
  @compile inline: [
             cache_result: 3,
             queries_in_request: 1,
             extract_caller_data: 1,
             export_api_call_data: 3,
             remote_ip: 1,
             user_agent: 1
           ]

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

    queries = queries_in_request(blueprint)
    export_api_call_data(queries, conn, blueprint)
    should_cache? = !Process.get(:do_not_cache_query)
    cache_result(should_cache?, queries, blueprint)

    conn
    |> maybe_create_or_drop_session(blueprint.execution.context)
  end

  # Do not cache in case of:
  # -`:nocache` returend from a resolver
  # - result is taken from the cache and should not be stored again. Storing
  # it again `touch`es it and the TTL timer is restarted. This can lead
  # to infinite storing the same value if there are enough requests
  defp cache_result(true, queries, blueprint) do
    all_queries_cachable? =
      queries
      |> Enum.all?(&Enum.member?(@cached_queries, Macro.underscore(&1)))

    if all_queries_cachable? do
      Cache.store(
        blueprint.execution.context.query_cache_key,
        blueprint.result
      )
    end
  end

  defp cache_result(_, _), do: :ok

  defp maybe_create_or_drop_session(conn, %{create_session: true, auth_token: auth_token}) do
    Plug.Conn.put_session(conn, :auth_token, auth_token)
  end

  defp maybe_create_or_drop_session(conn, %{delete_session: true}) do
    Plug.Conn.configure_session(conn, drop: true)
  end

  defp maybe_create_or_drop_session(conn, _), do: conn

  defp queries_in_request(%{operations: operations}) do
    operations
    |> Enum.flat_map(fn %{selections: selections} ->
      selections
      |> Enum.map(fn %{name: name} -> name end)
    end)
  end

  # API Call exporting functions

  defp export_api_call_data(queries, conn, blueprint) do
    now = DateTime.utc_now() |> DateTime.to_unix(:nanosecond)
    duration_ms = div(now - blueprint.telemetry.start_time, 1_000_000)

    {user_id, san_tokens, auth_method, api_token} =
      extract_caller_data(blueprint.execution.context)

    Enum.map(queries, fn query ->
      %{
        timestamp: div(now, 1_000_000_000),
        query: query,
        status_code: 200,
        user_id: user_id,
        auth_method: auth_method,
        api_token: api_token,
        remote_ip: remote_ip(blueprint),
        user_agent: user_agent(conn),
        duration_ms: duration_ms,
        san_tokens: san_tokens
      }
    end)
    |> Sanbase.ApiCallDataExporter.persist()
  end

  defp remote_ip(blueprint) do
    blueprint.execution.context.remote_ip |> :inet_parse.ntoa() |> to_string()
  end

  defp extract_caller_data(%{
         auth: %{auth_method: :user_token, current_user: user, san_balance: san_balance}
       }) do
    {user.id, san_balance, :jwt, nil}
  end

  defp extract_caller_data(%{
         auth: %{auth_method: :apikey, current_user: user, token: token, san_balance: san_balance}
       }) do
    {user.id, san_balance, :apikei, token}
  end

  defp extract_caller_data(%{
         auth: %{auth_method: :basic, san_balance: san_balance}
       }) do
    {nil, san_balance, :basic, nil}
  end

  defp extract_caller_data(_), do: {nil, nil, nil, nil}

  defp user_agent(%{req_headers: headers}) do
    Enum.find(headers, &match?({"user-agent", _}, &1))
    |> case do
      {"user-agent", user_agent} -> user_agent
      _ -> nil
    end
  end
end
