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
  alias Sanbase.Utils.IP

  @compile inline: [
             cache_result: 2,
             get_query_and_selector: 1,
             export_api_call_data: 3,
             extract_caller_data: 1,
             get_cache_key: 1,
             has_graphql_errors?: 1,
             maybe_create_or_drop_session: 2,
             queries_in_request: 1,
             remote_ip: 1
           ]

  @cached_queries [
    "allProjects",
    "allErc20Projects",
    "allProjectsByFunction",
    "allCurrencyProjects",
    "projectsListHistoryStats",
    "projectsListStats",
    "getMostRecent",
    "getMostVoted"
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
    do_not_cache? = Process.get(:do_not_cache_query) == true

    maybe_update_api_call_limit_usage(conn, blueprint.execution.context, Enum.count(queries))

    case do_not_cache? or has_graphql_errors?(blueprint) do
      true -> :ok
      false -> cache_result(queries, blueprint)
    end

    conn
    |> maybe_create_or_drop_session(blueprint.execution.context)
  end

  defp maybe_update_api_call_limit_usage(
         conn,
         %{
           rate_limiting_enabled: true,
           requested_product: "SANAPI",
           auth: %{current_user: user, auth_method: auth_method}
         },
         count
       ) do
    if conn.private[:has_api_call_limit_quota_infinity] != true,
      do: Sanbase.ApiCallLimit.update_usage(:user, user, count, auth_method)
  end

  defp maybe_update_api_call_limit_usage(
         conn,
         %{
           rate_limiting_enabled: true,
           requested_product: "SANAPI",
           remote_ip: remote_ip
         } = context,
         count
       ) do
    if conn.private[:has_api_call_limit_quota_infinity] != true do
      auth_method = context[:auth][:auth_method] || :unauthorized
      remote_ip = IP.ip_tuple_to_string(remote_ip)

      Sanbase.ApiCallLimit.update_usage(:remote_ip, remote_ip, count, auth_method)
    end
  end

  defp maybe_update_api_call_limit_usage(_conn, _context, _count), do: :ok

  defp cache_result(queries, blueprint) do
    all_queries_cachable? = queries |> Enum.all?(&Enum.member?(@cached_queries, &1))

    if all_queries_cachable? do
      Cache.store(
        get_cache_key(blueprint),
        blueprint.result
      )
    end
  end

  # The cache_key is the format of `{key, ttl}` or just `key`. Both cache keys
  # will be stored under the name `key` and in the first case only the ttl is
  # changed. This also means that if a value is stored as `{key, 300}` it can be
  # retrieved by using `{key, 10}` as in the case of `get` the ttl is ignored.
  # This allows us to change the cache_key produced in the DocumentProvider
  # and store it with a different ttl. The ttl is changed from the graphql cache
  # in case `caching_params` is provided.
  defp get_cache_key(blueprint) do
    case Process.get(:__change_absinthe_before_send_caching_ttl__) do
      ttl when is_number(ttl) ->
        {cache_key, _old_ttl} = blueprint.execution.context.query_cache_key

        {cache_key, ttl}

      _ ->
        blueprint.execution.context.query_cache_key
    end
  end

  defp maybe_create_or_drop_session(conn, %{create_session: true} = context) do
    SanbaseWeb.Guardian.add_jwt_tokens_to_conn_session(
      conn,
      Map.take(context, [:access_token, :refresh_token])
    )
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

    # Replace all occurences of getMetric and getSignal with names where
    # the metric or signal argument is also included
    queries =
      Map.get(blueprint.execution.context, :__get_query_name_arg__, []) ++
        Enum.reject(queries, &(&1 == "getMetric" or &1 == "getSignal"))

    Enum.map(queries, fn query ->
      # All ids in the batch need to be different so there's at least one field
      # that is different for all api calls, otherwise they can be squashed into
      # a single row when ingested in Clickhouse
      id =
        case Logger.metadata() |> Keyword.get(:request_id) do
          nil ->
            "gen_" <> (:crypto.strong_rand_bytes(16) |> Base.encode64())

          request_id ->
            request_id <> "_" <> (:crypto.strong_rand_bytes(6) |> Base.encode64())
        end

      {query, selector} = get_query_and_selector(query)

      bin_result = :erlang.term_to_binary(blueprint.result)

      %{
        timestamp: div(now, 1_000_000_000),
        id: id,
        query: query,
        selector: Jason.encode!(selector),
        status_code: 200,
        has_graphql_errors: has_graphql_errors?(blueprint),
        user_id: user_id,
        auth_method: auth_method,
        api_token: api_token,
        remote_ip: remote_ip(blueprint),
        user_agent: user_agent,
        duration_ms: duration_ms,
        san_tokens: san_tokens,
        response_size_byte: byte_size(bin_result),
        compressed_response_size_byte: byte_size(:zlib.gzip(bin_result))
      }
    end)
    |> Sanbase.Kafka.ApiCall.json_kv_tuple_no_hash_collision()
    |> Sanbase.KafkaExporter.persist_async(:api_call_exporter)
  end

  defp get_query_and_selector({:get_metric, _alias, metric, selector}),
    do: {"getMetric|#{metric}", selector}

  defp get_query_and_selector({:get_signal, _alias, signal, selector}),
    do: {"getSignal|#{signal}", selector}

  defp get_query_and_selector(query), do: {query, nil}

  defp remote_ip(blueprint) do
    blueprint.execution.context.remote_ip |> IP.ip_tuple_to_string()
  end

  defp extract_caller_data(%{
         auth: %{auth_method: :user_token, current_user: user}
       }) do
    {user.id, _san_balance = nil, :jwt, nil}
  end

  defp extract_caller_data(%{
         auth: %{auth_method: :apikey, current_user: user, token: token}
       }) do
    {user.id, _san_balance = nil, :apikey, token}
  end

  defp extract_caller_data(%{
         auth: %{auth_method: :basic}
       }) do
    {nil, _san_balance = nil, :basic, nil}
  end

  defp extract_caller_data(_), do: {nil, nil, nil, nil}

  defp has_graphql_errors?(%Absinthe.Blueprint{result: %{errors: _}}), do: true
  defp has_graphql_errors?(_), do: false
end
