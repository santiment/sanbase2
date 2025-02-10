defmodule SanbaseWeb.Graphql.Resolvers.QueriesResolver do
  @moduledoc false
  alias Sanbase.Dashboards
  alias Sanbase.Queries
  alias Sanbase.Queries.Executor.Result
  alias Sanbase.Queries.QueryMetadata

  require Logger

  # Query CRUD operations

  def get_query(_root, %{id: id}, resolution) do
    querying_user_id = get_in(resolution.context.auth, [:current_user, Access.key(:id)])
    Queries.get_query(id, querying_user_id)
  end

  def create_query(_root, %{} = args, %{context: %{auth: %{current_user: user}}}) do
    Queries.create_query(args, user.id)
  end

  def update_query(_root, %{id: id} = args, %{context: %{auth: %{current_user: user}}}) do
    parameters = Map.delete(args, :id)
    Queries.update_query(id, parameters, user.id)
  end

  def delete_query(_root, %{id: id}, %{context: %{auth: %{current_user: user}}}) do
    Queries.delete_query(id, user.id)
  end

  def get_user_queries(_root, %{page: page, page_size: page_size} = args, resolution) do
    querying_user_id = get_in(resolution.context.auth, [:current_user, Access.key(:id)])
    queried_user_id = Map.get(args, :user_id, querying_user_id)

    if is_nil(queried_user_id) do
      {:error, "Error getting user queries: neither userId is provided, nor the query is executed by a logged in user."}
    else
      Queries.get_user_queries(
        queried_user_id,
        querying_user_id,
        page: page,
        page_size: page_size
      )
    end
  end

  def get_public_queries(_root, %{page: page, page_size: page_size}, _resolution) do
    Queries.get_public_queries(page: page, page_size: page_size)
  end

  # Run query operations

  def run_sql_query(_root, %{id: query_id}, %{context: %{auth: %{current_user: user}} = context} = resolution) do
    with :ok <-
           Queries.user_can_execute_query(user, context.subscription_product, context.auth.plan),
         {:ok, query} <- Queries.get_query(query_id, user.id) do
      Process.put(
        :queries_dynamic_repo,
        Queries.user_plan_to_dynamic_repo(context.subscription_product, context.auth.plan)
      )

      query_metadata = QueryMetadata.from_resolution(resolution)
      Queries.run_query(query, user, query_metadata)
    end
  end

  def run_raw_sql_query(
        _root,
        %{sql_query_text: query_text, sql_query_parameters: query_parameters},
        %{context: %{auth: %{current_user: user}} = context} = resolution
      ) do
    # There is some issue with setting `%{}` as default parameters, so we continue to use
    # "{}" and parse it properly here, before passing it on.
    query_parameters = if query_parameters == "{}", do: %{}, else: query_parameters

    with :ok <-
           Queries.user_can_execute_query(user, context.subscription_product, context.auth.plan) do
      Process.put(
        :queries_dynamic_repo,
        Queries.user_plan_to_dynamic_repo(context.subscription_product, context.auth.plan)
      )

      query_metadata = QueryMetadata.from_resolution(resolution)
      query = Queries.get_ephemeral_query_struct(query_text, query_parameters, user)
      Queries.run_query(query, user, query_metadata)
    end
  end

  def run_dashboard_sql_query(
        _root,
        %{dashboard_id: dashboard_id, dashboard_query_mapping_id: mapping_id} = args,
        %{context: %{auth: %{current_user: user, plan: plan}, subscription_product: product}} = resolution
      ) do
    parameters_override = Map.get(args, :parameters_override, %{})
    force_parameters_override = Map.get(args, :force_parameters_override, false)
    query_metadata = QueryMetadata.from_resolution(resolution)
    cache? = Map.get(args, :store_execution, false)

    # get_dashboard_query/3 is a function that returns a query struct with the
    # query's local parameter being overriden by the dashboard global parameters
    with :ok <- Queries.user_can_execute_query(user, product, plan),
         {:ok, query} <-
           Queries.get_dashboard_query(
             dashboard_id,
             mapping_id,
             user.id,
             parameters_override,
             force_parameters_override
           ),
         :ok <- Queries.process_put_dynamic_repo(product, plan),
         {:ok, result} <- Queries.run_query(query, user, query_metadata),
         :ok <-
           maybe_cache_execution(
             cache?,
             result,
             dashboard_id,
             mapping_id,
             parameters_override,
             user
           ) do
      {:ok, result}
    end
  end

  defp maybe_cache_execution(false = _cache?, _, _, _, _, _), do: :ok

  defp maybe_cache_execution(true, result, dashboard_id, mapping_id, parameters_override, user) do
    result =
      Dashboards.cache_dashboard_query_execution(
        dashboard_id,
        parameters_override,
        mapping_id,
        result,
        user.id
      )

    case result do
      {:ok, _} -> :ok
      error -> error
    end
  end

  # Dashboard CRUD operations

  def get_dashboard(_root, %{id: id}, resolution) do
    querying_user_id = get_in(resolution.context.auth, [:current_user, Access.key(:id)])

    with {:ok, dashboard} <- Dashboards.get_dashboard(id, querying_user_id) do
      # For backwards compatibility, properly provide the panels.
      # The Frontend will migrate to queries once they detect panels
      dashboard = atomize_dashboard_panels_sql_keys(dashboard)
      {:ok, dashboard}
    end
  end

  def get_user_dashboards(_root, %{page: page, page_size: page_size} = args, resolution) do
    querying_user_id = get_in(resolution.context.auth, [:current_user, Access.key(:id)])
    queried_user_id = Map.get(args, :user_id, querying_user_id)

    if is_nil(queried_user_id) do
      {:error,
       "Error getting user dashboards: neither userId is provided, nor the query is executed by a logged in user."}
    else
      Dashboards.user_dashboards(
        queried_user_id,
        querying_user_id,
        page: page,
        page_size: page_size
      )
    end
  end

  def create_dashboard(_root, %{} = args, %{context: %{auth: %{current_user: user}}}) do
    Dashboards.create_dashboard(args, user.id)
  end

  def update_dashboard(_root, %{id: id} = args, %{context: %{auth: %{current_user: user}}}) do
    args = Map.delete(args, :id)
    Dashboards.update_dashboard(id, args, user.id)
  end

  def delete_dashboard(_root, %{id: id}, %{context: %{auth: %{current_user: user}}}) do
    Dashboards.delete_dashboard(id, user.id)
  end

  # Query-Dashboard interactions

  def create_dashboard_query(_root, %{dashboard_id: dashboard_id, query_id: query_id} = args, %{
        context: %{auth: %{current_user: user}}
      }) do
    Dashboards.add_query_to_dashboard(
      dashboard_id,
      query_id,
      user.id,
      Map.get(args, :settings, %{})
    )
  end

  def update_dashboard_query(
        _root,
        %{dashboard_id: dashboard_id, dashboard_query_mapping_id: mapping_id, settings: settings},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.update_dashboard_query(dashboard_id, mapping_id, user.id, settings)
  end

  def delete_dashboard_query(_root, %{dashboard_id: dashboard_id, dashboard_query_mapping_id: mapping_id}, %{
        context: %{auth: %{current_user: user}}
      }) do
    Dashboards.remove_query_from_dashboard(dashboard_id, mapping_id, user.id)
  end

  defp transform_cache_input(data) do
    # data is the gzip compressed and base64 encoded query JSON
    with {:ok, result_string} <- Queries.Executor.Result.decode_and_decompress(data),
         {:ok, %Result{} = result} <- Queries.Executor.Result.from_json_string(result_string),
         true <- Result.all_fields_present?(result) do
      {:ok, result}
    end
  end

  def cache_query_execution(
        _root,
        %{query_id: query_id, compressed_query_execution_result: compressed_query_execution_result},
        %{context: %{auth: %{current_user: user}}}
      ) do
    with {:ok, result} <- transform_cache_input(compressed_query_execution_result),
         {:ok, _} <- Queries.cache_query_execution(query_id, result, user.id) do
      {:ok, true}
    end
  end

  def get_cached_query_executions(_root, %{query_id: query_id}, resolution) do
    querying_user_id = get_in(resolution.context.auth, [:current_user, Access.key(:id)])

    with {:ok, caches} <- Sanbase.Queries.get_cached_query_executions(query_id, querying_user_id) do
      result =
        Enum.map(caches, fn cache ->
          %{
            result: Sanbase.Queries.Cache.decode_decompress_result(cache.data),
            user: cache.user,
            inserted_at: cache.inserted_at,
            is_query_hash_matching: cache.is_query_hash_matching
          }
        end)

      {:ok, result}
    end
  end

  def cache_dashboard_query_execution(
        _root,
        %{
          dashboard_id: dashboard_id,
          dashboard_query_mapping_id: mapping_id,
          compressed_query_execution_result: compressed_query_execution_result
        },
        %{context: %{auth: %{current_user: user}}}
      ) do
    with {:ok, result} <- transform_cache_input(compressed_query_execution_result),
         {:ok, dashboard_cache} <-
           Dashboards.cache_dashboard_query_execution(
             dashboard_id,
             _parameters_override = %{},
             mapping_id,
             result,
             user.id
           ) do
      queries = Map.values(dashboard_cache.queries)

      {:ok, %{queries: queries}}
    end
  end

  def get_cached_dashboard_queries_executions(_root, %{dashboard_id: dashboard_id} = args, resolution) do
    querying_user_id = get_in(resolution.context.auth, [:current_user, Access.key(:id)])

    parameters_override = Map.get(args, :parameters_override, %{})

    with {:ok, dashboard_cache} <-
           Dashboards.get_cached_dashboard_queries_executions(
             dashboard_id,
             parameters_override,
             querying_user_id
           ) do
      queries = Map.values(dashboard_cache.queries)
      {:ok, %{queries: queries}}
    end
  end

  # Dashboard Global Parameters CRUD (without explicit read)

  def add_dashboard_global_parameter(_root, %{dashboard_id: dashboard_id, key: key, value: value_map}, %{
        context: %{auth: %{current_user: user}}
      }) do
    with {:ok, value} <- get_global_param_one_value(value_map) do
      Dashboards.add_global_parameter(dashboard_id, user.id, key: key, value: value)
    end
  end

  def update_dashboard_global_parameter(_root, %{dashboard_id: dashboard_id, key: key} = args, %{
        context: %{auth: %{current_user: user}}
      }) do
    opts = args |> Map.take([:new_key, :new_value]) |> Keyword.new()

    case opts do
      [] ->
        {:error, "Error update dashboard global parameter: neither new_key nor new_value provided"}

      [_ | _] ->
        opts = Keyword.put(opts, :key, key)
        # If `new_value` is set, transform it to a single value.
        # If it is set, but with an error, `with` will return an error.
        # If `new_value` is not provided, the `else` branch will be executed.
        if new_value_map = Keyword.get(opts, :new_value) do
          with {:ok, new_value} <- get_global_param_one_value(new_value_map) do
            opts = Keyword.put(opts, :new_value, new_value)
            Dashboards.update_global_parameter(dashboard_id, user.id, opts)
          end
        else
          Dashboards.update_global_parameter(dashboard_id, user.id, opts)
        end
    end
  end

  def delete_dashboard_global_parameter(_root, %{dashboard_id: dashboard_id, key: key}, %{
        context: %{auth: %{current_user: user}}
      }) do
    Dashboards.delete_global_parameter(dashboard_id, user.id, dashboard_parameter_key: key)
  end

  # Dashboard Global parameter Overrides CRUD (without explicit read)

  def add_dashboard_global_parameter_override(
        _root,
        %{
          dashboard_id: dashboard_id,
          dashboard_query_mapping_id: mapping_id,
          dashboard_parameter_key: dashboard_parameter_key,
          query_parameter_key: query_parameter_key
        },
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.add_global_parameter_override(
      dashboard_id,
      mapping_id,
      user.id,
      query_parameter_key: query_parameter_key,
      dashboard_parameter_key: dashboard_parameter_key
    )
  end

  def delete_dashboard_global_parameter_override(
        _root,
        %{
          dashboard_id: dashboard_id,
          dashboard_query_mapping_id: mapping_id,
          dashboard_parameter_key: dashboard_parameter_key
        },
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.delete_global_parameter_override(
      dashboard_id,
      mapping_id,
      user.id,
      dashboard_parameter_key: dashboard_parameter_key
    )
  end

  # Exectutions Histiory

  def get_clickhouse_query_execution_stats(_root, %{clickhouse_query_id: clickhouse_query_id}, _resolution) do
    case Queries.QueryExecution.get_execution_stats(clickhouse_query_id) do
      {:ok, %{execution_details: details} = result} ->
        # For legacy reasons the API response is flat.
        result = result |> Map.delete(:execution_details) |> Map.merge(details)
        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
  end

  def get_query_execution(_root, %{clickhouse_query_id: clickhouse_query_id}, %{context: %{auth: %{current_user: user}}}) do
    Queries.get_query_execution(clickhouse_query_id, user.id)
  end

  def get_query_executions(_root, %{page: page, page_size: page_size}, %{context: %{auth: %{current_user: user}}}) do
    Queries.get_user_query_executions(user.id, page: page, page_size: page_size)
  end

  # Text Widgets

  def add_dashboard_text_widget(_root, %{dashboard_id: dashboard_id} = args, %{context: %{auth: %{current_user: user}}}) do
    args = Map.delete(args, :dashboard_id)
    Dashboards.add_text_widget(dashboard_id, user.id, args)
  end

  def update_dashboard_text_widget(_root, %{dashboard_id: dashboard_id, text_widget_id: text_widget_id} = args, %{
        context: %{auth: %{current_user: user}}
      }) do
    args = Map.drop(args, [:dashboard_id, :text_widget_id])
    Dashboards.update_text_widget(dashboard_id, text_widget_id, user.id, args)
  end

  def delete_dashboard_text_widget(_root, %{dashboard_id: dashboard_id, text_widget_id: text_widget_id}, %{
        context: %{auth: %{current_user: user}}
      }) do
    Dashboards.delete_text_widget(dashboard_id, text_widget_id, user.id)
  end

  # Image Widgets

  def add_dashboard_image_widget(_root, %{dashboard_id: dashboard_id} = args, %{context: %{auth: %{current_user: user}}}) do
    Dashboards.add_image_widget(dashboard_id, user.id, args)
  end

  def update_dashboard_image_widget(_root, %{dashboard_id: dashboard_id, image_widget_id: text_widget_id} = args, %{
        context: %{auth: %{current_user: user}}
      }) do
    Dashboards.update_image_widget(dashboard_id, text_widget_id, user.id, args)
  end

  def delete_dashboard_image_widget(_root, %{dashboard_id: dashboard_id, image_widget_id: text_widget_id}, %{
        context: %{auth: %{current_user: user}}
      }) do
    Dashboards.delete_image_widget(dashboard_id, text_widget_id, user.id)
  end

  def atomize_dashboard_panels_sql_keys(struct) do
    panels = Enum.map(struct.panels, &atomize_panel_sql_keys/1)

    Map.put(struct, :panels, panels)
  end

  def atomize_panel_sql_keys(panel) do
    case panel do
      %{sql: %{} = sql} ->
        atomized_sql =
          sql
          |> Map.new(fn
            {k, v} when is_binary(k) ->
              # Ignore old, no longer existing keys like san_query_id
              try do
                {String.to_existing_atom(k), v}
              rescue
                _ -> {nil, nil}
              end

            {k, v} ->
              {k, v}
          end)
          |> Map.delete(nil)

        %{panel | sql: atomized_sql}

      panel ->
        panel
    end
  end

  # Private functions

  defp get_global_param_one_value(value_map) do
    if map_size(value_map) == 1 do
      value = value_map |> Map.values() |> List.first()
      {:ok, value}
    else
      {:error, "Error adding dashboard global parameter: the `value` input object must set only a single field"}
    end
  end
end
