defmodule SanbaseWeb.Graphql.AbsintheBeforeSend do
  @moduledoc ~s"""
  Cache & Persist API Call Data right before sending the response.

  This module is responsible for persisting the API Call data and
  cache the whole result of some queries right before it is send to the client.

  All queries that did not raise exceptions and were successfully handled
  by the GraphQL layer pass through this module. The data for them is exported
  to Kafka. See `export_api_call_data` for more info.

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

  @compile inline: [
             construct_query_name: 1,
             cache_result: 2,
             queries_in_request: 1,
             extract_caller_data: 1,
             export_api_call_data: 3,
             remote_ip: 1,
             has_graphql_errors?: 1,
             maybe_create_or_drop_session: 2
           ]

  @product_id_api Sanbase.Billing.Product.product_api()

  @cached_queries [
    "allProjects",
    "allErc20Projects",
    "allCurrencyProjects",
    "projectsListHistoryStats",
    "projectsListStats",
    "allProjectsByFunction"
  ]

  def cached_queries(), do: @cached_queries

  def before_send(conn, %Absinthe.Blueprint{} = blueprint) do
    # Do not cache in case of:
    # -`:nocache` returend from a resolver
    # - result is taken from the cache and should not be stored again. Storing
    # it again `touch`es it and the TTL timer is restarted. This can lead
    # to infinite storing the same value if there are enough requests

    queries = queries_in_request(blueprint)
    export_api_call_data(queries, conn, blueprint)
    do_not_cache? = is_nil(Process.get(:do_not_cache_query))

    maybe_update_api_call_limit_usage(blueprint.execution.context, Enum.count(queries))

    case do_not_cache? or has_graphql_errors?(blueprint) do
      true -> :ok
      false -> cache_result(queries, blueprint)
    end

    conn
    |> maybe_create_or_drop_session(blueprint.execution.context)
  end

  defp maybe_update_api_call_limit_usage(
         %{
           rate_limiting_enabled: true,
           product_id: @product_id_api,
           auth: %{current_user: user, auth_method: auth_method}
         },
         count
       ) do
    Sanbase.ApiCallLimit.update_usage(:user, user, count, auth_method)
  end

  defp maybe_update_api_call_limit_usage(
         %{
           rate_limiting_enabled: true,
           product_id: @product_id_api,
           remote_ip: remote_ip
         } = context,
         count
       ) do
    auth_method = context[:auth][:auth_method] || :unauthorized
    remote_ip = remote_ip |> :inet_parse.ntoa() |> to_string()

    Sanbase.ApiCallLimit.update_usage(:remote_ip, remote_ip, count, auth_method)
  end

  defp maybe_update_api_call_limit_usage(_, _), do: :ok

  defp cache_result(queries, blueprint) do
    all_queries_cachable? = queries |> Enum.all?(&Enum.member?(@cached_queries, &1))

    if all_queries_cachable? do
      Cache.store(
        blueprint.execution.context.query_cache_key,
        blueprint.result
      )
    end
  end

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
      |> Enum.map(fn %{name: name} -> Inflex.camelize(name, :lower) end)
    end)
  end

  # API Call exporting functions

  # Create an API Call event for every query in a Document separately.
  defp export_api_call_data(queries, conn, blueprint) do
    now = DateTime.utc_now() |> DateTime.to_unix(:nanosecond)
    now_mono = System.monotonic_time()
    duration_ms = div(now_mono - blueprint.telemetry.start_time_mono, 1_000_000)
    duration_ms = Enum.max([duration_ms, 0])
    user_agent = Plug.Conn.get_req_header(conn, "user-agent") |> List.first()

    {user_id, san_tokens, auth_method, api_token} =
      extract_caller_data(blueprint.execution.context)

    # Replace all occurences of getMetric and getAnomaly with names where
    # the metric or anomaly argument is also included
    queries =
      Map.get(blueprint.execution.context, :__get_query_name_arg__, []) ++
        Enum.reject(queries, &(&1 == "getMetric" or &1 == "getAnomaly"))

    id =
      Logger.metadata() |> Keyword.get(:request_id) ||
        "gen_" <> (:crypto.strong_rand_bytes(16) |> Base.encode64())

    Enum.map(queries, fn query ->
      %{
        timestamp: div(now, 1_000_000_000),
        id: id,
        query: query |> construct_query_name(),
        status_code: 200,
        has_graphql_errors: has_graphql_errors?(blueprint),
        user_id: user_id,
        auth_method: auth_method,
        api_token: api_token,
        remote_ip: remote_ip(blueprint),
        user_agent: user_agent,
        duration_ms: duration_ms,
        san_tokens: san_tokens
      }
    end)
    |> Sanbase.Kafka.ApiCall.json_kv_tuple()
    |> Sanbase.KafkaExporter.persist(:api_call_exporter)
  end

  defp construct_query_name({:get_metric, metric}), do: "getMetric|#{metric}"
  defp construct_query_name({:get_anomaly, anomaly}), do: "getAnomaly|#{anomaly}"
  defp construct_query_name(query), do: query

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
    {user.id, san_balance, :apikey, token}
  end

  defp extract_caller_data(%{
         auth: %{auth_method: :basic, san_balance: san_balance}
       }) do
    {nil, san_balance, :basic, nil}
  end

  defp extract_caller_data(_), do: {nil, nil, nil, nil}

  defp has_graphql_errors?(%Absinthe.Blueprint{result: %{errors: _}}), do: true
  defp has_graphql_errors?(_), do: false
end
