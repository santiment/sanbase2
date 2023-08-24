defmodule SanbaseWeb.Graphql.Schema.DashboardQueries do
  @moduledoc ~s"""
  Queries and mutations for authentication related intercations
  """
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.DashboardResolver
  alias SanbaseWeb.Graphql.Middlewares.{UserAuth, JWTAuth}

  object :dashboard_queries do
    @desc ~s"""
    Get metadata bout the Clickhouse database exposed for the SQL Editor.

    The metadata about the Clickhouse database includes information
    about the columns, tables and functions. This information can be used
    for displaying info to user and also in the autocomplete implementation
    """
    field :get_clickhouse_database_metadata, :clickhouse_database_metadata do
      meta(access: :free)

      arg(:functions_filter, :clickhouse_metadata_function_filter_enum)

      cache_resolve(&DashboardResolver.get_clickhouse_database_metadata/3)
    end

    @desc ~s"""
    Get a list of clickhouse tables that the users can access
    via the SQL editor.
    """
    field :get_available_clickhouse_tables, list_of(:clickhouse_table_definition) do
      meta(access: :free)
      resolve(&DashboardResolver.get_available_clickhouse_tables/3)
    end

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

    @desc ~s"""
    Get the last computed version of a Dashboard Cache.

    This API returns a single Dashboard Panel Cache, the same
    as the one returned by getDashboardCache
    """
    field :get_dashboard_panel_cache, :panel_cache do
      meta(access: :free)
      arg(:dashboard_id, non_null(:integer))
      arg(:panel_id, non_null(:string))

      resolve(&DashboardResolver.get_dashboard_panel_cache/3)
    end

    @desc ~s"""
    Get a history revision of the dashboard schema, identified by the
    dashboard id and hash.

    The history revision contains the same fields as the dashboard schema
    and is enriched with a comment, a computed hash that identifies the
    revision and datetime fields indicating when it was created.
    """
    field :get_dashboard_schema_history, :dashboard_schema_history do
      meta(access: :free)

      arg(:id, non_null(:integer))
      arg(:hash, non_null(:string))

      middleware(JWTAuth)

      resolve(&DashboardResolver.get_dashboard_schema_history/3)
    end

    @desc ~s"""
    Get a list of all stored history revisionf of the dashboard schema, identified
    by the dashboard id.

    The returned result is a list of previews, including the hash, comment and creation
    datetime. The hash is used to obtain the full dashboard history revision.
    """
    field :get_dashboard_schema_history_list, list_of(:dashboard_schema_history_preview) do
      meta(access: :free)

      arg(:id, non_null(:integer))
      arg(:page, non_null(:integer))
      arg(:page_size, non_null(:integer))

      middleware(JWTAuth)

      resolve(&DashboardResolver.get_dashboard_schema_history_list/3)
    end

    @desc ~s"""
    Every SQL query executed in Clickhouse is uniquely identified by an id.

    This unique id is called `clickhouseQueryId` throught our API. If it is
    provided back to thi query by the user that executed it, it returns
    data about the execution of the query - how much RAM memory it used,
    how many gigabytes/rows were read, how big is the result, how much CPU
    time it used, etc.
    """
    field :get_clickhouse_query_execution_stats, :query_execution_stats do
      meta(access: :free)
      arg(:clickhouse_query_id, non_null(:string))

      middleware(JWTAuth)
      resolve(&DashboardResolver.get_clickhouse_query_execution_stats/3)
    end

    @desc ~s"""
    Compute the raw Clickhouse SQL query defined by the arguments.

    This mutation is used to execute some SQL outside the context of
    dasbhoards and panels.

    Example:

    {
     computeRawClickhouseQuery(
      query: "SELECT * FROM intraday_metrics WHERE asset_id IN (SELECT asset_id FROM asset_metadata WHERE name = {{slug}}) LIMIT {{limit}}"
      parameters: "{\"slug\": \"bitcoin\", \"limit\": 1}"){
        columns
        rows
      }
    }
    """
    field :compute_raw_clickhouse_query, :query_result do
      meta(access: :free)
      arg(:query, non_null(:string))
      arg(:parameters, non_null(:json))

      middleware(UserAuth)

      cache_resolve(&DashboardResolver.compute_raw_clickhouse_query/3,
        ttl: 10,
        max_ttl_offset: 10
      )
    end

    field :generate_title_by_query, :query_human_description do
      meta(access: :free)
      arg(:sql_query_text, non_null(:string))

      middleware(UserAuth)

      resolve(&DashboardResolver.generate_title_by_query/3)
    end
  end

  object :dashboard_mutations do
    @desc ~s"""
    Create an empty (without panels) dashboard.

    A dashboard is holding together panels, each defining a
    Clickhouse SQL query and how to visualize it. The dashboard
    usually has a topic it is about and the panels in it show
    different types of information about that topic.

    The dashboard is created with its name, description, parameters and public
    status. Public dashboards are visible to all users.

    In order to manipulate the panels of the dashboard, refer to the
    createDashboardPanel/updateDashboardPanel/removeDashboardPanel
    mutations.

    Dashboard holds the global parameters that are shared by all panels.
    """
    field :create_dashboard, :dashboard_schema do
      arg(:name, non_null(:string))
      arg(:description, :string)
      arg(:is_public, :boolean)
      arg(:parameters, :json)

      middleware(JWTAuth)

      resolve(&DashboardResolver.create_dashboard/3)
    end

    @desc ~s"""
    Update the name, description, parameters or public status of a dashboard.

    In order to manipulate the panels of the dashboard, refer to the
    createDashboardPanel/updateDashboardPanel/removeDashboardPanel
    mutations.
    """
    field :update_dashboard, :dashboard_schema do
      arg(:id, non_null(:integer))

      arg(:name, :string)
      arg(:description, :string)
      arg(:is_public, :boolean)
      arg(:parameters, :json)

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
    and optionally parameters of that query and information how to visualize it.

    The panel inherits the dashboard parameters when it is being computed, so a
    panel can define only the SQL query and no parameters.

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
      arg(:panel, non_null(:panel_schema_input_object))

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
      arg(:panel, non_null(:panel_schema_input_object_for_update))

      middleware(JWTAuth)

      resolve(&DashboardResolver.update_dashboard_panel/3)
    end

    @desc ~s"""
    Remove a dashboard panel.

    Only the owner of the dashboard can remove a panel from it.
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

    @desc ~s"""
    Update the dashboard cache with the provided data.

    This mutation, along with computeDashboardPanel, provides
    the capabilities to compute and store dashboard panel results
    separately. In contrast to computeAndStoreDashboardPanel, having
    the methods separated allows users to compute many different panel
    configurations and only store the result of the one that satisfies
    the requirements.

    All the panel fields are required.

    The `rows` and `summary` fields must be JSON encoded.

    Example:

    mutation {
      storeDashboardPanel(
        dashboardId: 134
        panelId: "c5a3b5dd-0e31-42ae-954a-83b741818a28"
        panel: {
            clickhouseQueryId: "177a5a3d-072b-48ac-8cf5-d8375c8314ef"
            columns: ["asset_id", "metric_id", "dt", "value", "computed_at"]
            columnTypes: ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"]
            queryEndTime: "2022-06-14T12:08:10Z"
            queryStartTime: "2022-06-14T12:08:10Z"
            rows: "[[2503,250,\"2008-12-10T00:00:00Z\",0.0,\"2020-02-28T15:18:42Z\"],[2503,250,\"2008-12-10T00:05:00Z\",0.0,\"2020-02-28T15:18:42Z\"]]"
            summary: "{\"read_bytes\":\"0\",\"read_rows\":\"0\",\"total_rows_to_read\":\"0\",\"written_bytes\":\"0\",\"written_rows\":\"0\"}"
        }
      ){
        id
        clickhouseQueryId
        dashboardId
        columns
        rows
        summary
        updatedAt
        queryStartTime
        queryEndTime
      }
    }
    """
    field :store_dashboard_panel, :panel_cache do
      arg(:dashboard_id, non_null(:integer))
      arg(:panel_id, non_null(:string))
      arg(:panel, non_null(:computed_panel_schema_input_object))

      middleware(JWTAuth)
      resolve(&DashboardResolver.store_dashboard_panel/3)
    end

    field :compute_raw_clickhouse_query, :query_result do
      deprecate("Use the query with the same name instead of a mutation")
      arg(:query, non_null(:string))
      arg(:parameters, non_null(:json))

      middleware(UserAuth)

      cache_resolve(&DashboardResolver.compute_raw_clickhouse_query/3,
        ttl: 10,
        max_ttl_offset: 10
      )
    end

    @desc ~s"""
    Store the dashboard schema to allow to revisit it again in the future.

    The schema is stored in the database alongside a comment added by the
    author. All fields and the current datetime are used to generate a hash,
    similar to git commit hashes, that uniquely identifies the revision.
    """
    field :store_dashboard_schema_history, :dashboard_schema_history do
      arg(:id, non_null(:integer))
      arg(:message, non_null(:string))

      middleware(JWTAuth)

      resolve(&DashboardResolver.store_dashboard_schema_history/3)
    end
  end
end
