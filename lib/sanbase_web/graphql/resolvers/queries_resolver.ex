defmodule SanbaseWeb.Graphql.Resolvers.QueriesResolver do
  alias Sanbase.Queries
  alias Sanbase.Dashboards
  alias Sanbase.Queries.QueryMetadata

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
        %{user_id: user_id, page: page, page_size: page_size},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Queries.get_user_queries(
      _queried_user_id = user_id,
      _querying_user_id = user.id,
      page: page,
      page_size: page_size
    )
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
        %{query_id: query_id},
        %{context: %{auth: %{current_user: user}} = context} = resolution
      ) do
    with :ok <- Queries.user_can_execute_query(user.id, context.product_code, context.auth.plan),
         {:ok, query} <- Queries.get_query(query_id, user.id) do
      query_metadata = QueryMetadata.from_resolution(resolution)
      Queries.run_query(query, user.id, query_metadata)
    end
  end

  def run_raw_sql_query(
        _root,
        %{sql_query_text: query_text, sql_query_parameters: query_parameters},
        %{context: %{auth: %{current_user: user}} = context} = resolution
      ) do
    with :ok <- Queries.user_can_execute_query(user.id, context.product_code, context.auth.plan),
         query = Queries.get_ephemeral_query_struct(query_text, query_parameters) do
      query_metadata = QueryMetadata.from_resolution(resolution)
      Queries.run_query(query, user.id, query_metadata)
    end
  end

  def run_dashboard_sql_query(
        _root,
        %{dashboard_id: dashboard_id, dashboard_query_mapping_id: mapping_id},
        %{context: %{auth: %{current_user: user}} = context} = resolution
      ) do
    # get_dashboard_query/3 is a function that returns a query struct with the
    # query's local parameter being overriden by the dashboard global parameters
    with :ok <- Queries.user_can_execute_query(user.id, context.product_code, context.auth.plan),
         query = Queries.get_dashboard_query(dashboard_id, mapping_id, user.id) do
      query_metadata = QueryMetadata.from_resolution(resolution)
      Queries.run_query(query, user.id, query_metadata)
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
        %{dashboard_id: dashboard_id, query_id: query_id, settings: settings},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.add_query_to_dashboard(dashboard_id, query_id, user.id, settings)
  end

  def update_dashboard_query(
        _root,
        %{dashboard_id: dashboard_id, dashboard_query_mapping_id: mapping_id, settings: settings},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.update_dashboard_query(dashboard_id, mapping_id, settings, user.id)
  end

  def delete_dashboard_query(
        _root,
        %{dashboard_id: dashboard_id, dashboard_query_mapping_id: mapping_id},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.remove_query_from_dashboard(dashboard_id, mapping_id, user.id)
  end

  # Dashboard Global Parameters CRUD (without explicit read)

  def add_dashboard_global_parameter(
        _root,
        %{dashboard_id: dashboard_id, key: key, value: value},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.add_global_parameter(dashboard_id, user.id, key: key, value: value)
  end

  def update_dashboard_global_parameter(
        _root,
        %{dashboard_id: dashboard_id} = args,
        %{context: %{auth: %{current_user: user}}}
      ) do
    opts = Map.take(args, [:new_key, :new_value]) |> Keyword.new()

    case opts do
      [] ->
        {:error, "Error update dashboard global parameter: neither new key nor value provided"}

      [_ | _] ->
        Dashboards.update_global_parameter(dashboard_id, user.id, opts)
    end
  end

  def delete_dashboard_global_parameter(
        _root,
        %{dashboard_id: dashboard_id, key: key},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.delete_global_parameter(dashboard_id, user.id, key)
  end

  # Dashboard Global Paramter Overrides CRUD (without explicit read)

  def add_dashboard_global_parameter_override(
        _root,
        %{
          dashboard_id: dashboard_id,
          dashboard_query_mapping_id: mapping_id,
          global_parameter: global,
          local_parameter: local
        },
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.add_global_parameter_override(
      dashboard_id,
      mapping_id,
      user.id,
      local: local,
      global: global
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

  def get_queries_executions(
        _root,
        %{page: page, page_size: page_size},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Queries.get_user_query_executions(user, page: page, page_size: page_size)
  end
end
