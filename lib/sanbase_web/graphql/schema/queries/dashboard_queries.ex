defmodule SanbaseWeb.Graphql.Schema.DashboardQueries do
  @moduledoc ~s"""
  Queries and mutations for authentication related intercations
  """
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

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
    Create an empty (without panels) dashboard.

    A dashboard is holding together panels, each defining a
    Clickhouse SQL query and how to visualize it. The dashboard
    usually has a topic it is about and the panels in it show
    different types of information about that topic.

    The dashboard is created with its name, description and public
    status. Public dashboards are visible to all users.

    In order to manipulate the panels of the dashboard, refer to the
    createDashboardPanel/updateDashboardPanel/removeDashboardPanel
    mutations.
    """
    field :create_dashboard, :dashboard_schema do
      arg(:name, non_null(:string))
      arg(:description, :string)
      arg(:is_public, :boolean)

      middleware(JWTAuth)

      resolve(&DashboardResolver.create_dashboard/3)
    end

    @desc ~s"""
    Update the name, description or public status of a dashboard.

    In order to manipulate the panels of the dashboard, refer to the
    createDashboardPanel/updateDashboardPanel/removeDashboardPanel
    mutations.
    """
    field :update_dashboard, :dashboard_schema do
      arg(:id, non_null(:integer))

      arg(:name, :string)
      arg(:description, :string)
      arg(:is_public, :boolean)

      middleware(JWTAuth)

      resolve(&DashboardResolver.update_dashboard/3)
    end

    @desc ~s"""
    Remove a dashboard.

    In order to manipulate the panels of the dashboard, refer to the
    createDashboardPanel/updateDashboardPanel/removeDashboardPanel
    mutations.
    """
    field :remove_dashboard, :dashboard_schema do
      arg(:id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&DashboardResolver.delete_dashboard/3)
    end

    @desc ~s"""
    Add a panel to a dashboard.

    A panel is an entity that contains a Clickhouse SQL query,
    parameters of that query and information how to visualize it.

    The panel's SQL must be valid Clickhouse SQL. It can access only
    some of the tables in the database. The system tables are not accessible.

    Parametrization is done via templating - the places that need to be filled
    are indicated by the following syntax {{<key>}}. Example: WHERE address = {{address}}
    The parameters are provided as a JSON map.

    Example:

      mutation {
        createDashboardPanel(
          dashboardId: 1
          panel: {
            name: "Some metrics table"
            description: "show some rows from the intraday metrics table for bitcoin"
            sql: {
              parameters: "{\"limit\":20,\"slug\":\"bitcoin\"}"
              query: "SELECT * FROM intraday_metrics WHERE asset_id IN (SELECT asset_id FROM asset_metadata WHERE name = {{slug}} LIMIT {{limit}})"
            }
            position: "{\"x\":0,\"y\":0}"
            type: TABLE

          }
        ){
          id
          dashboardId
          sql {
            query
            parameters
          }
        }
      }
    """
    field :create_dashboard_panel, :panel_schema do
      arg(:dashboard_id, non_null(:integer))
      arg(:panel, non_null(:panel_input_object))

      middleware(JWTAuth)

      resolve(&DashboardResolver.create_dashboard_panel/3)
    end

    @desc ~s"""
    Update a dashboard panel.

    Refer to the documentation of createDashboardPanel for description
    of the fields of the panel
    """
    field :update_dashboard_panel, :panel_schema do
      arg(:dashboard_id, non_null(:integer))
      arg(:panel_id, non_null(:string))
      arg(:panel, non_null(:panel_input_object))

      middleware(JWTAuth)

      resolve(&DashboardResolver.update_dashboard_panel/3)
    end

    @desc ~s"""
    Remove a dashboard panel
    """
    field :remove_dashboard_panel, :panel_schema do
      arg(:dashboard_id, non_null(:integer))
      arg(:panel_id, non_null(:string))

      middleware(JWTAuth)

      resolve(&DashboardResolver.remove_dashboard_panel/3)
    end

    @desc ~s"""
    Compute a dashboard panel without storing the result in the cache.

    A dashboard panel is computed by executing the SQL query with the
    given parameters.

    The response contains information about the result and information
    about the computation.
    """
    field :compute_dashboard_panel, :panel_cache do
      arg(:dashboard_id, non_null(:integer))
      arg(:panel_id, non_null(:string))

      middleware(JWTAuth)

      resolve(&DashboardResolver.compute_dashboard_panel/3)
    end

    @desc ~s"""
    Compute a dashboard panel and store the result in the cache.

    The response is the same as the one of computeDashboardPanel.
    The difference is that that result is stored in the cache and can
    then be obtained via the getDashboardCache query
    """
    field :compute_and_store_dashboard_panel, :panel_cache do
      arg(:dashboard_id, non_null(:integer))
      arg(:panel_id, non_null(:string))

      middleware(JWTAuth)

      resolve(&DashboardResolver.compute_and_store_dashboard_panel/3)
    end

    field :store_dashboard_panel, :panel_cache do
      arg(:dashboard_id, non_null(:integer))
      arg(:panel_id, non_null(:string))
      arg(:panel, non_null(:computed_panel_input_object))

      middleware(JWTAuth)
      resolve(&DashboardResolver.store_dashboard_panel/3)
    end

    @desc ~s"""
    Compute the raw Clickhouse SQL query defined by the arguments.

    This mutation is used to execute some SQL outside the context of
    dasbhoards and panels.

    Example:

    mutation{
     computeRawClickhouseQuery(
      query: "SELECT * FROM intraday_metrics WHERE asset_id IN (SELECT asset_id FROM asset_metadata WHERE name = {{slug}}) LIMIT {{limit}}"
      parameters: "{\"slug\": \"bitcoin\", \"limit\": 1}"){
        columns
        rows
      }
    }
    """
    field :compute_raw_clickhouse_query, :query_result do
      arg(:query, non_null(:string))
      arg(:parameters, non_null(:json))

      middleware(JWTAuth)

      cache_resolve(&DashboardResolver.compute_raw_clickhouse_query/3,
        ttl: 10,
        max_ttl_offset: 10
      )
    end
  end
end
