defmodule SanbaseWeb.Graphql.Resolvers.QueriesResolver do
  @moduledoc ~s"""
  Module with resolvers connected to the Apikey authentication. All the logic
  is delegated to the `Apikey` module
  """

  alias Sanbase.Queries
  alias Sanbase.Dashboards
  alias Sanbase.Queries.Query
  alias Sanbase.Queries.QueryMetadata

  require Logger

  # Query CRUD operations

  def get_query(_root, %{query_id: query_id}, %{context: %{auth: %{current_user: user}}}) do
    Queries.get_query(query_id, user.id)
  end

  def create_query(_root, %{} = args, %{context: %{auth: %{current_user: user}}}) do
    Queries.create_query(args, user.id)
  end

  def update_query(_root, %{query_id: query_id, parameters: parameters}, %{
        context: %{auth: %{current_user: user}}
      }) do
    Queries.update_query(query_id, parameters, user.id)
  end

  def delete_query(_root, %{query_id: query_id}, %{context: %{auth: %{current_user: user}}}) do
    Queries.delete_query(query_id, user.id)
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
        %{context: %{auth: %{current_user: user}}} = resolution
      ) do
    with :ok <- Queries.user_can_execute_query(user.id),
         {:ok, query} <- Queries.get_query(query_id, user.id) do
      query_metadata = QueryMetadata.from_resolution(resolution)
      Queries.run_query(query, query_metadata, user.id)
    end
  end

  def run_raw_sql_query(
        _root,
        %{sql_query: query, sql_parameters: parameters},
        %{context: %{auth: %{current_user: user}}} = resolution
      ) do
    with :ok <- Queries.user_can_execute_query(user.id),
         %Query{} = query <- Queries.get_ephemeral_query_struct(query, parameters) do
      query_metadata = QueryMetadata.from_resolution(resolution)
      Queries.run_query(query, query_metadata, user.id)
    end
  end

  def run_dashboard_sql_query(
        _root,
        %{dashboard_id: dashboard_id, dashboard_query_mapping_id: mapping_id},
        %{context: %{auth: %{current_user: user}}} = resolution
      ) do
    # get_dashboard_query/3 is a function that returns a query struct with the
    # query's local parameter being overriden by the dashboard global parameters
    with :ok <- Queries.user_can_execute_query(user.id),
         %Query{} = query <- Queries.get_dashboard_query(dashboard_id, mapping_id, user.id) do
      query_metadata = QueryMetadata.from_resolution(resolution)
      Queries.run_query(query, query_metadata, user.id)
    end
  end

  # Dashboard CRUD operations

  def get_dashboard(
        _root,
        %{dashboard_id: dashboard_id},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.get_dashboard(dashboard_id, user.id)
  end

  def create_dashboard(
        _root,
        %{parameters: parameters},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.create_dashboard(parameters, user.id)
  end

  def update_dashboard(
        _root,
        %{dashboard_id: dashboard_id, parameters: parameters},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.update_dashboard(dashboard_id, parameters, user.id)
  end

  def delete_dashboard(
        _root,
        %{dashboard_id: dashboard_id},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.delete_dashboard(dashboard_id, user.id)
  end

  # Query-Dashboard interactions

  # TODO: Think about name unification
  def add_query_to_dashboard(
        _root,
        %{dashboard_id: dashboard_id, query_id: query_id, settings: settings},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.add_query_to_dashboard(dashboard_id, query_id, settings, user.id)
  end

  def update_dashboard_query(
        _root,
        %{dashboard_id: dashboard_id, dashboard_query_mapping_id: mapping_id, settings: settings},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.update_dashboard_query(dashboard_id, mapping_id, settings, user.id)
  end

  def remove_query_from_dashboard(
        _root,
        %{dashboard_id: dashboard_id, dashboard_query_mapping_id: mapping_id},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Dashboards.remove_query_from_dashboard(dashboard_id, mapping_id, user.id)
  end

  # Past Exectutions

  def get_queries_executions(
        _root,
        %{page: page, page_size: page_size},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Queries.get_user_query_executions(user, page: page, page_size: page_size)
  end
end
