defmodule SanbaseWeb.Graphql.Schema.DashboardQueries do
  @moduledoc ~s"""
  Queries and mutations for authentication related intercations
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.DashboardResolver

  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

  object :dashboard_queries do
    @desc ~s"""
    Get the schema of a dashboard.

    The schema is the defintion of the dashboard and its panels.
    The definitions include:
    - the name, description and public status of the dashboard.
    - the panels in the dashboard, described by their name, type,
      SQL query and arguments, etc.

    It does not contain any result data that is produced by SQL
    queries in the dashboard. The results can be obtained by the
    getDashboardCache query.
    """
    field :get_dashboard_schema, :dashboard_schema do
      meta(access: :free)
      arg(:id, non_null(:integer))

      resolve(&DashboardResolver.get_dashboard_schema/3)
    end

    @desc ~s"""
    Get the last computed version of a dashboard.

    The query returns a list of the last computation of every
    panel. The panel computation (cache) is described by its
    id and a JSON-formatted string of the result. The result
    contains the column names, the column types, the rows and
    the time they were computed. The SQL and arguments that
    were used to compute the result can be found in the dashhboard
    schema, fetched by the getDashboardSchema query.

    This is called a cache because only the latest result is
    stored and all previous states are discarded. Storing data
    for long time after other computations and changes are done
    is done via snapshots (to be implemented).
    """
    field :get_dashboard_cache, :dashboard_cache do
      meta(access: :free)
      arg(:id, non_null(:integer))

      resolve(&DashboardResolver.get_dashboard_cache/3)
    end
  end

  object :dashboard_mutations do
    @desc ~s"""
    TODO: Write me before merging
    """
    field :create_dashboard, :dashboard_schema do
      arg(:name, non_null(:string))
      arg(:description, :string)
      arg(:is_public, :boolean)

      middleware(JWTAuth)

      resolve(&DashboardResolver.create_dashboard/3)
    end

    field :update_dashboard, :dashboard_schema do
      arg(:id, non_null(:integer))

      arg(:name, :string)
      arg(:description, :string)
      arg(:is_public, :boolean)

      middleware(JWTAuth)

      resolve(&DashboardResolver.update_dashboard/3)
    end

    field :remove_dashboard, :dashboard_schema do
      arg(:id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&DashboardResolver.delete_dashboard/3)
    end

    @desc ~s"""
    TODO: Write me before merging
    """
    field :create_dashboard_panel, :panel_schema do
      arg(:dashboard_id, non_null(:integer))
      arg(:panel, non_null(:panel_input_object))

      middleware(JWTAuth)

      resolve(&DashboardResolver.create_dashboard_panel/3)
    end

    @desc ~s"""
    TODO: Write me before merging
    """
    field :remove_dashboard_panel, :panel_schema do
      arg(:dashboard_id, non_null(:integer))
      arg(:panel_id, non_null(:string))

      middleware(JWTAuth)

      resolve(&DashboardResolver.remove_dashboard_panel/3)
    end

    @desc ~s"""
    TODO: Write me before merging
    """
    field :update_dashboard_panel, :panel_schema do
      arg(:dashboard_id, non_null(:integer))
      arg(:panel_id, non_null(:string))
      arg(:panel, non_null(:panel_input_object))

      middleware(JWTAuth)

      resolve(&DashboardResolver.update_dashboard_panel/3)
    end

    @desc ~s"""
    TODO: Write me before merging
    """
    field :compute_dashboard_panel, :panel_cache do
      arg(:dashboard_id, non_null(:integer))
      arg(:panel_id, non_null(:string))

      middleware(JWTAuth)

      resolve(&DashboardResolver.compute_dashboard_panel/3)
    end

    field :compute_raw_clickhouse_query, :query_result do
      arg(:query, non_null(:string))
      arg(:parameters, non_null(:json))

      middleware(JWTAuth)

      resolve(&DashboardResolver.compute_raw_clickhouse_query/3)
    end

    @desc ~s"""
    TODO: Write me before merging
    """
    field :compute_and_store_dashboard_panel, :panel_cache do
      arg(:dashboard_id, non_null(:integer))
      arg(:panel_id, non_null(:string))

      middleware(JWTAuth)

      resolve(&DashboardResolver.compute_and_store_dashboard_panel/3)
    end
  end
end
