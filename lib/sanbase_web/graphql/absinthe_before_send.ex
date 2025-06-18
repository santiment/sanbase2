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
             maybe_cache_result: 2,
             get_query_and_selector: 1,
             export_api_call_data: 1,
             maybe_update_api_call_limit_usage: 1,
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
    %{success: success_queries, error: error_queries} = get_queries_in_document(blueprint)

    # If there are no successful queries, it means that we returned just an error to the user.
    # Error queries are not exported and they do not bump the API calls count of the user.
    #
    # NOTE: In the future we could export the error queries in a separate Kafka topic that
    # we can use to analyze user errors and notify the user in case of increased amount of errors.
    # One of the more famous errors is that the asset that is queried is not supported or is mistyped.
    # Users might miss that a lot of their queries fail with this error.
    if success_queries != [] do
      query_metadata = query_metadata(conn, blueprint, success_queries, error_queries)

      maybe_async(fn -> export_api_call_data(query_metadata) end)
      maybe_async(fn -> maybe_update_api_call_limit_usage(query_metadata) end)

      # In some cases the resolver asks for the query to not be cached.
      # In some cases this is done because the result depends on the user who queried it.
      do_not_cache? = Process.get(:do_not_cache_query) == true

      # Do not cache in case of:
      # -`:nocache` returend from a resolver. This is handled inside the Cache implementation itself
      # - result is taken from the cache and should not be stored again. Storing
      #   it again `touch`es it and the TTL timer is restarted. This can lead
      #   to infinite storing the same value if there are enough requests
      # - Some resolver has explicitly asked not to cache the result by putting
      #   do_not_cache_query flag in the process dictionary
      case do_not_cache? or error_queries != [] do
        true -> :ok
        # The pre_override_queries are the getMetric and getSignal query names
        # before they got renamed to getMetric|<metric> and getSignal|<signal>
        false -> maybe_cache_result(query_metadata.queries, blueprint)
      end
    end

    conn
    |> maybe_create_or_drop_session(blueprint.execution.context)
  end

  case Application.compile_env(:sanbase, :env) do
    :test -> defp maybe_async(fun), do: fun.()
    _ -> defp maybe_async(fun), do: Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fun)
  end

  defp query_metadata(conn, blueprint, success_queries, error_queries) do
    now_mono = System.monotonic_time()
    duration_ms = div(now_mono - blueprint.telemetry.start_time_mono, 1_000_000)
    duration_ms = Enum.max([duration_ms, 0])
    user_agent = Plug.Conn.get_req_header(conn, "user-agent") |> List.first()

    result_sizes = result_sizes(blueprint)

    caller_data =
      extract_caller_data(blueprint.execution.context)

    partial_context =
      Map.take(blueprint.execution.context, [
        :auth,
        :rate_limiting_enabled,
        :requested_product,
        :remote_ip
      ])

    queries = success_queries ++ error_queries

    %{
      timestamp: DateTime.utc_now() |> DateTime.to_unix(:second),
      has_graphql_errors: has_graphql_errors?(blueprint),
      has_api_call_limit_quota_infinity: conn.private[:has_api_call_limit_quota_infinity],
      duration_ms: duration_ms,
      user_agent: user_agent,
      queries: queries,
      success_queries: success_queries,
      success_queries_count: length(success_queries),
      error_queries: error_queries,
      result_sizes: result_sizes,
      caller_data: caller_data,
      remote_ip: remote_ip(blueprint),
      partial_context: partial_context
    }
  end

  defp result_sizes(%{result: result = _blueprint}) do
    byte_result = :erlang.term_to_binary(result)
    byte_size = byte_result |> byte_size()
    compressed_byte_size = byte_result |> :zlib.gzip() |> byte_size()

    %{
      byte_size: byte_size,
      compressed_byte_size: compressed_byte_size,
      min_byte_size: min(byte_size, compressed_byte_size)
    }
  end

  defp maybe_update_api_call_limit_usage(
         %{
           partial_context: %{
             rate_limiting_enabled: true,
             requested_product: "SANAPI",
             auth: %{current_user: user}
           }
         } = query_metadata
       ) do
    if query_metadata.has_api_call_limit_quota_infinity != true do
      Sanbase.ApiCallLimit.update_usage(
        :user,
        query_metadata.caller_data.auth_method,
        user,
        query_metadata.success_queries_count,
        query_metadata.result_sizes.min_byte_size
      )
    end
  end

  defp maybe_update_api_call_limit_usage(
         %{
           partial_context: %{
             rate_limiting_enabled: true,
             requested_product: "SANAPI",
             remote_ip: remote_ip
           }
         } = query_metadata
       )
       when is_tuple(remote_ip) do
    if query_metadata.has_api_call_limit_quota_infinity != true do
      auth_method = query_metadata.caller_data.auth_method || :unauthorized
      remote_ip = IP.ip_tuple_to_string(remote_ip)

      Sanbase.ApiCallLimit.update_usage(
        :remote_ip,
        auth_method,
        remote_ip,
        query_metadata.success_queries_count,
        query_metadata.result_sizes.min_byte_size
      )
    end
  end

  defp maybe_update_api_call_limit_usage(_query_metadata), do: :ok

  defp maybe_cache_result(queries, blueprint) do
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
    # We need to use both the name and the alias in order to properly export only the successful ones
    # And also to count them
    operations
    |> Enum.flat_map(fn %{selections: selections} ->
      selections
      |> Enum.map(fn %{name: name, alias: alias} ->
        name = Inflex.camelize(name, :lower)
        {alias || name, Inflex.camelize(name, :lower)}
      end)
    end)
    |> Map.new()
  end

  # API Call exporting functions

  # Create an API Call event for every query in a Document separately.
  defp export_api_call_data(query_metadata) when is_map(query_metadata) do
    Enum.map(query_metadata.success_queries, fn query ->
      {query, selector} = get_query_and_selector(query)

      %{
        id: generate_id(),
        timestamp: query_metadata.timestamp,
        query: query,
        selector: Jason.encode!(selector),
        status_code: 200,
        has_graphql_errors: query_metadata.has_graphql_errors,
        user_id: query_metadata.caller_data.user_id,
        san_tokens: query_metadata.caller_data.san_balance,
        auth_method: query_metadata.caller_data.auth_method,
        api_token: query_metadata.caller_data.api_token,
        remote_ip: query_metadata.remote_ip,
        user_agent: query_metadata.user_agent,
        duration_ms: query_metadata.duration_ms,
        response_size_byte: query_metadata.result_sizes.byte_size,
        compressed_response_size_byte: query_metadata.result_sizes.compressed_byte_size
      }
    end)
    |> Sanbase.Kafka.ApiCall.json_kv_tuple_no_hash_collision()
    |> Sanbase.KafkaExporter.persist_async(:api_call_exporter)
  end

  defp generate_id() do
    # All ids in the batch need to be different so there's at least one field
    # that is different for all api calls, otherwise they can be squashed into
    # a single row when ingested in Clickhouse
    case Logger.metadata() |> Keyword.get(:request_id) do
      nil ->
        "gen_" <> (:crypto.strong_rand_bytes(16) |> Base.encode64())

      request_id ->
        request_id <> "_" <> (:crypto.strong_rand_bytes(6) |> Base.encode64())
    end
  end

  defp get_query_and_selector({:get_metric, _alias, metric, selector}),
    do: {"getMetric|#{metric}", selector}

  defp get_query_and_selector({:get_signal, _alias, signal, selector}),
    do: {"getSignal|#{signal}", selector}

  defp get_query_and_selector(query), do: {query, nil}

  defp remote_ip(blueprint) do
    if Map.has_key?(blueprint.execution.context, :remote_ip),
      do: blueprint.execution.context.remote_ip |> IP.ip_tuple_to_string(),
      else: ""
  end

  defp extract_caller_data(%{
         auth: %{auth_method: :user_token, current_user: user}
       }) do
    %{user_id: user.id, san_balance: nil, auth_method: :jwt, api_token: nil}
  end

  defp extract_caller_data(%{
         auth: %{auth_method: :apikey, current_user: user, api_token: token}
       }) do
    %{user_id: user.id, san_balance: nil, auth_method: :apikey, api_token: token}
  end

  defp extract_caller_data(%{
         auth: %{auth_method: :basic}
       }) do
    %{user_id: nil, san_balance: nil, auth_method: :basic, api_token: nil}
  end

  defp extract_caller_data(_),
    do: %{user_id: nil, san_balance: nil, auth_method: nil, api_token: nil}

  defp get_queries_in_document(blueprint) do
    # queries_in_request/1 returns a map in the format %{"alias" => "query_name"}.
    # GraphQL aliases are defined as:
    # { price_usd: getMetric(metric: "price_usd") ... }
    # In case of no alias, the query name itself is put as key
    #
    # This allows us to check the `data` and `errors` fields in the result and deduce which queries succeeded
    # and which failed. These fields use the aliases names, but when we export the API call we need to record
    # the actual GraphQL query used, so instead of `myCustomAlias123` we need to record `getMetric|price_usd`.
    alias_to_query_name_map = queries_in_request(blueprint)

    # Get the list of all aliases.
    # In case of no `errors` field -- all queries succeeded, so we direclty return it.
    # In case no `data` field -- all queries failed, so we return all aliases as errors.
    # Before returning, the aliases will be renamed to the actual query names
    all_aliases = Map.keys(alias_to_query_name_map)

    case blueprint.result do
      # If there is data it means at least some of the queries succeeded.
      # If the document has multiple queries, some of them still could have failed,
      # but not with graphql-level critical error. Such errors include checks we perform
      # after the documented is checked to be a valid GraphQL error.
      # Such checks can include authorization errors -- user does not have access with
      # their subscription plan, non existent metric or asset, etc.
      %{data: data, errors: errors} when is_map(data) and is_list(errors) ->
        error_queries = errors |> Enum.map(fn %{path: [name | _]} -> name end)
        success_queries = all_aliases -- error_queries

        %{
          success: success_queries,
          error: error_queries
        }

      # Only successful queries, none failed.
      %{data: data} = map when is_map(data) and not is_map_key(map, :errors) ->
        %{success: all_aliases, error: []}

      # If there is no 'data' then we do not return any result, so all queries
      # in the request have failed. Some queries can fail because there is some breaking
      # GraphQL error in another query -- mistyped field, type violation, etc.
      %{errors: errors} = map when is_list(errors) and not is_map_key(map, :data) ->
        %{
          success: [],
          error: all_aliases
        }
    end
    |> rename_aliases_to_query_names(alias_to_query_name_map, blueprint)
  end

  defp rename_aliases_to_query_names(
         %{success: success, error: error},
         alias_to_query_name_map,
         %Absinthe.Blueprint{} = blueprint
       )
       when is_map(alias_to_query_name_map) do
    # The TransformResolution middleware is used in getMetric and getSignal APIs
    # to enrich them so we can export also the name of the metric/signal that has been queried.
    # This allows us to better see what exactly has been called -- instead of just seeing
    # `getMetric`, we enrich it with some of the arguments that have been passed to it -- meric name and selector.
    # Additionally, this middleware also records the GraphQL alias provided by the user,
    # which is later used to resolve aliases to query names.

    # Get a map where the values are one of:
    # - {:get_metric, alias, metric, selector} |
    # - {:get_signal, alias, signal, selector} |
    # These will replace the `alias: getMetric` seen in the queries list in order
    # to enrich them with the metric/signal that has been queried by the user
    #
    # and the keys are the alias itself.
    alias_to_get_query_tuple_map =
      Map.get(blueprint.execution.context, :__get_query_name_arg__, [])
      |> Map.new(fn
        {:get_metric, alias, _metric, _selector} = tuple -> {alias, tuple}
        {:get_signal, alias, _signal, _selector} = tuple -> {alias, tuple}
      end)

    # Rename aliases to the query name itself, or in case of getMetric and getSignal -- the the whole tuple.
    # The tuple is used in export_api_call_data/1 to construct the query name (like getMetric|price_usd) and
    # the selector that has been provided (like {"slugs": ["bitcoin", "ethereum"]})
    rename_mapper = fn list ->
      Enum.map(list, fn alias ->
        Map.get(alias_to_get_query_tuple_map, alias) || Map.fetch!(alias_to_query_name_map, alias)
      end)
    end

    %{success: rename_mapper.(success), error: rename_mapper.(error)}
  end

  defp has_graphql_errors?(%Absinthe.Blueprint{result: %{errors: _}}), do: true
  defp has_graphql_errors?(_), do: false
end
