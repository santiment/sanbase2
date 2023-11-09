defmodule SanbaseWeb.Graphql.Resolvers.QueriesResolver do
  alias Sanbase.Queries
  alias Sanbase.Dashboards
  alias Sanbase.Queries.QueryMetadata
  alias Sanbase.Queries.Executor.Result

  require Logger

  # Query CRUD operations

  def get_query(_root, %{id: id}, %{context: %{auth: %{current_user: user}}}) do
    Queries.get_query(id, user.id)
  end

  def create_query(_root, %{} = args, %{context: %{auth: %{current_user: user}}}) do
    Queries.create_query(args, user.id)
  end

  def update_query(_root, %{id: id} = args, %{
        context: %{auth: %{current_user: user}}
      }) do
    parameters = Map.delete(args, :id)
    Queries.update_query(id, parameters, user.id)
  end

  def delete_query(_root, %{id: id}, %{context: %{auth: %{current_user: user}}}) do
    Queries.delete_query(id, user.id)
  end

  def get_user_queries(
        _root,
        %{page: page, page_size: page_size} = args,
        resolution
      ) do
    querying_user_id = get_in(resolution.context.auth, [:current_user, Access.key(:id)])
    queried_user_id = Map.get(args, :user_id, querying_user_id)

    if not is_nil(queried_user_id) do
      Queries.get_user_queries(
        queried_user_id,
        querying_user_id,
        page: page,
        page_size: page_size
      )
    else
      {:error,
       "Error getting user queries: neither userId is provided, nor the query is executed by a logged in user."}
    end
  end

  def get_public_queries(
        _root,
        %{page: page, page_size: page_size},
        _resolution
      ) do
    Queries.get_public_queries(page: page, page_size: page_size)
  end

  # Run query operations

  def run_sql_query(
        _root,
        %{id: query_id},
        %{context: %{auth: %{current_user: user}} = context} = resolution
      ) do
    with :ok <- Queries.user_can_execute_query(user, context.product_code, context.auth.plan),
         {:ok, query} <- Queries.get_query(query_id, user.id) do
      query_metadata = QueryMetadata.from_resolution(resolution)
      Queries.run_query(query, user, query_metadata)
    end
  end

  def run_raw_sql_query(
        _root,
        %{sql_query_text: query_text, sql_query_parameters: query_parameters},
        %{context: %{auth: %{current_user: user}} = context} = resolution
      ) do
    with :ok <- Queries.user_can_execute_query(user, context.product_code, context.auth.plan),
         query = Queries.get_ephemeral_query_struct(query_text, query_parameters, user) do
      query_metadata = QueryMetadata.from_resolution(resolution)
      Queries.run_query(query, user, query_metadata)
    end
  end

  def run_dashboard_sql_query(
        _root,
        %{dashboard_id: dashboard_id, dashboard_query_mapping_id: mapping_id},
        %{context: %{auth: %{current_user: user}} = context} = resolution
      ) do
    # get_dashboard_query/3 is a function that returns a query struct with the
    # query's local parameter being overriden by the dashboard global parameters
    with :ok <- Queries.user_can_execute_query(user, context.product_code, context.auth.plan),
         {:ok, query} <- Queries.get_dashboard_query(dashboard_id, mapping_id, user.id) do
      query_metadata = QueryMetadata.from_resolution(resolution)
      Queries.run_query(query, user, query_metadata)
    end
  end

  # Dashboard CRUD operations

  def get_dashboard(
        _root,
        %{id: id},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.get_dashboard(id, user.id)
  end

  def get_user_dashboards(
        _root,
        %{page: page, page_size: page_size} = args,
        resolution
      ) do
    querying_user_id = get_in(resolution.context.auth, [:current_user, Access.key(:id)])
    queried_user_id = Map.get(args, :user_id, querying_user_id)

    if not is_nil(queried_user_id) do
      Dashboards.user_dashboards(
        queried_user_id,
        querying_user_id,
        page: page,
        page_size: page_size
      )
    else
      {:error,
       "Error getting user dashboards: neither userId is provided, nor the query is executed by a logged in user."}
    end
  end

  def create_dashboard(
        _root,
        %{} = args,
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.create_dashboard(args, user.id)
  end

  def update_dashboard(
        _root,
        %{id: id} = args,
        %{context: %{auth: %{current_user: user}}}
      ) do
    args = Map.delete(args, :id)
    Dashboards.update_dashboard(id, args, user.id)
  end

  def delete_dashboard(
        _root,
        %{id: id},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.delete_dashboard(id, user.id)
  end

  # Query-Dashboard interactions

  def create_dashboard_query(
        _root,
        %{dashboard_id: dashboard_id, query_id: query_id} = args,
        %{context: %{auth: %{current_user: user}}}
      ) do
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

  def delete_dashboard_query(
        _root,
        %{dashboard_id: dashboard_id, dashboard_query_mapping_id: mapping_id},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.remove_query_from_dashboard(dashboard_id, mapping_id, user.id)
  end

  def store_dashboard_query_execution(
        _root,
        %{
          dashboard_id: dashboard_id,
          dashboard_query_mapping_id: mapping_id,
          compressed_query_execution_result: compressed_query_execution_result
        },
        %{context: %{auth: %{current_user: user}}}
      ) do
    with {:ok, result_string} <- Result.decode_and_decompress(compressed_query_execution_result),
         {:ok, query_execution_result} <- Result.from_json_string(result_string),
         {:ok, dashboard_cache} <-
           Dashboards.store_dashboard_query_execution(
             dashboard_id,
             mapping_id,
             query_execution_result,
             user.id
           ) do
      queries = Map.values(dashboard_cache.queries)

      {:ok, %{queries: queries}}
    end
  end

  def get_cached_dashboard_queries_executions(_root, %{dashboard_id: dashboard_id}, resolution) do
    querying_user_id = get_in(resolution.context.auth, [:current_user, Access.key(:id)])

    with {:ok, dashboard_cache} <-
           Dashboards.get_cached_dashboard_queries_executions(dashboard_id, querying_user_id) do
      queries = Map.values(dashboard_cache.queries)
      {:ok, %{queries: queries}}
    end
  end

  # Dashboard Global Parameters CRUD (without explicit read)

  def add_dashboard_global_parameter(
        _root,
        %{dashboard_id: dashboard_id, key: key, value: value_map},
        %{context: %{auth: %{current_user: user}}}
      ) do
    with {:ok, value} <- get_global_param_one_value(value_map) do
      Dashboards.add_global_parameter(dashboard_id, user.id, key: key, value: value)
    end
  end

  def update_dashboard_global_parameter(
        _root,
        %{dashboard_id: dashboard_id, key: key} = args,
        %{context: %{auth: %{current_user: user}}}
      ) do
    opts =
      args
      |> Map.take([:new_key, :new_value])
      |> Keyword.new()
      |> Keyword.put(:key, key)

    case opts do
      [] ->
        {:error, "Error update dashboard global parameter: neither new key nor value provided"}

      [_ | _] ->
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

  def delete_dashboard_global_parameter(
        _root,
        %{dashboard_id: dashboard_id, key: key},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.delete_global_parameter(dashboard_id, user.id, key)
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
          key: key
        },
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.add_global_parameter_override(
      dashboard_id,
      mapping_id,
      user.id,
      key
    )
  end

  # Exectutions Histiory

  def get_query_execution(
        _root,
        %{clickhouse_query_id: clickhouse_query_id},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Queries.get_query_execution(clickhouse_query_id, user.id)
  end

  def get_query_executions(
        _root,
        %{page: page, page_size: page_size},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Queries.get_user_query_executions(user.id, page: page, page_size: page_size)
  end

  # Text Widgets

  def add_dashboard_text_widget(_root, %{dashboard_id: dashboard_id} = args, %{
        context: %{auth: %{current_user: user}}
      }) do
    Dashboards.add_text_widget(dashboard_id, user.id, args)
  end

  def update_dashboard_text_widget(
        _root,
        %{dashboard_id: dashboard_id, text_widget_id: text_widget_id} = args,
        %{
          context: %{auth: %{current_user: user}}
        }
      ) do
    Dashboards.update_text_widget(dashboard_id, text_widget_id, user.id, args)
  end

  def delete_dashboard_text_widget(
        _root,
        %{dashboard_id: dashboard_id, text_widget_id: text_widget_id},
        %{
          context: %{auth: %{current_user: user}}
        }
      ) do
    Dashboards.delete_text_widget(dashboard_id, text_widget_id, user.id)
  end

  # Private functions

  defp get_global_param_one_value(value_map) do
    if map_size(value_map) == 1 do
      value = Map.values(value_map) |> List.first()
      {:ok, value}
    else
      {:error,
       "Error adding dashboard global parameter: the `value` input object must set only a single field"}
    end
  end
end
