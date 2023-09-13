defmodule SanbaseWeb.Graphql.Schema.QueriesQueries do
  @moduledoc ~s"""
  Queries and mutations for authentication related intercations
  """
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.QueriesResolver
  # alias SanbaseWeb.Graphql.Resolvers.DashboardResolver
  alias SanbaseWeb.Graphql.Middlewares.UserAuth
  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

  object :queries_queries do
    @desc ~s"""
    Fetch a query by its id.

    The SQL Query is an entity that encapsulates a Clickhouse SQL query, the
    query parameters and the query metadata (name, description, etc.).

    The query can be public or private. Public queries are visible to all users,
    while private queries are visible only to the user that created them.
    """
    field :get_sql_query, :sql_query do
      meta(access: :free)

      arg(:id, non_null(:integer))

      middleware(UserAuth)

      resolve(&QueriesResolver.get_query/3)
    end

    @desc ~s"""
    Fetch a list of the queries that belong to a user.
    If the querying user is the same as the queried user, both public and private
    queries are returned. If the querying user is different from the queried user,
    only the public queries are shown.
    """
    field :get_user_queries, list_of(:sql_query) do
      meta(access: :free)

      arg(:user_id, non_null(:integer))

      arg(:page, non_null(:integer))
      arg(:page_size, non_null(:integer))

      cache_resolve(&QueriesResolver.get_user_queries/3, ttl: 10, max_ttl_offset: 20)
    end

    @desc ~s"""
    Fetch a list of the public queries. Includes queries of all users, including
    the current querying user.
    """
    field :get_public_queries, list_of(:sql_query) do
      meta(access: :free)

      arg(:page, non_null(:integer))
      arg(:page_size, non_null(:integer))

      cache_resolve(&QueriesResolver.get_public_queries/3, ttl: 10, max_ttl_offset: 20)
    end

    @desc ~s"""
    Fetch a list of the queries executions of the current user.

    The list of executions can be additonally filtered by the query_id
    """
    field :get_queries_executions, list_of(:sql_query_execution_stats) do
      meta(access: :free)

      arg(:page, non_null(:integer))
      arg(:page_size, non_null(:integer))

      arg(:query_id, :integer)

      middleware(UserAuth)

      resolve(&QueriesResolver.get_queries_executions/3)
    end

    @desc ~s"""
    Compute the raw Clickhouse SQL query defined by the provided query and parameters.
    The query is defined as a string and the parameters are defined as a JSON map. The query
    is not stored in the database, and is only executed once.

    Example:

    {
      runRawSqlQuery(
        sqlQueryText: "SELECT * FROM intraday_metrics WHERE asset_id IN (SELECT asset_id FROM asset_metadata WHERE name = {{slug}}) LIMIT {{limit}}"
        sqlQueryParameters: "{\"slug\": \"bitcoin\", \"limit\": 1}"){
          columns
          rows
      }
    }
    """
    field :run_raw_sql_query, :sql_query_execution_result do
      meta(access: :free)

      arg(:sql_query_text, non_null(:string))
      arg(:sql_query_parameters, non_null(:json))

      middleware(UserAuth)

      resolve(&QueriesResolver.run_raw_sql_query/3)
    end

    @desc ~s"""
    Compute the query asidentified by the id. The query can be computed only if the
    querying user has read access to it (owns the query or the query is public).

    The query is executed with its own set of parameters

    The computed result is not stored in the database.
    """
    field :run_sql_query, :sql_query_execution_result do
      meta(access: :free)

      arg(:id, non_null(:integer))

      middleware(UserAuth)

      resolve(&QueriesResolver.run_sql_query/3)
    end

    @desc ~s"""
    Compute the query as identified by the dashboard_query_mapping_id in the context
    of dashboard_id. The query is identified by the mapping id as one query can be
    added multiple times to a dashboard with different (global override) parameters.
    The query must already be added to the dashboard.
    The query can be computed only if the querying user has read access to it --
    the user either owns the query or the query is public.

    The query local parameters are overriden by the dashboard parameters, if such
    overriding is defined. The dashboard global parameters are used to easily
    change the parameters of all the queries in the dashboard, without having to
    change each query individually, or without requiring all the queries to have
    parameters with the same name.

    The computed result is not stored in the database.
    """
    field :run_dashboard_sql_query, :sql_query_execution_result do
      meta(access: :free)

      arg(:dashboard_id, non_null(:integer))
      arg(:dashboard_query_mapping_id, non_null(:integer))

      middleware(UserAuth)

      resolve(&QueriesResolver.run_dashboard_sql_query/3)
    end
  end

  object :queries_mutations do
    @desc ~s"""
    Create a new SQL Query.

    The origin_id field can be filled with the id of another query. This is used
    when one wants to create a copy/fork of another query. The origin_id can be used
    to track the original query's changes and to update the forked query accordingly,
    if needed.

    The sql_query_text and sql_query_parameters hold the actual query and its parameters.

    The settings field contains arbitrary JSON data that can be used to store any
    extra parameters relevant to the frontend.

    Example:

    mutation{
      createSqlQuery(
        name: "Some records"
        description: "An example of a select statement with parameters"
        isPublic: true
        sqlQueryText: "SELECT * FROM intraday_metrics WHERE asset_id IN (SELECT asset_id FROM asset_metadata WHERE name = {{slug}}) LIMIT {{limit}}"
        sqlQueryParameters: "{\"slug\": \"bitcoin\", \"limit\": 1}"
        settings: "{\"anyKey\": \"anyValue\", \"layout\": [0,1,2,3,4,5]}"){
          id
          name
          description
          isPublic
          sqlQueryText
          sqlQueryParameters
      }
    }
    """
    field :create_sql_query, :sql_query do
      arg(:origin_id, :integer)
      arg(:name, :string)
      arg(:description, :string)
      arg(:is_public, :boolean)
      arg(:sql_query_text, :string)
      arg(:sql_query_parameters, :json)
      arg(:settings, :json)

      middleware(JWTAuth)

      resolve(&QueriesResolver.create_query/3)
    end

    @desc ~s"""
    Update the fields of an existing SQL query, identified by the query_id.
    Only the owner of the query can update it.
    """
    field :update_sql_query, :sql_query do
      arg(:query_id, non_null(:integer))

      arg(:origin_id, :integer)
      arg(:name, :string)
      arg(:description, :string)
      arg(:is_public, :boolean)
      arg(:sql_query_text, :string)
      arg(:sql_query_parameters, :json)
      arg(:settings, :json)

      middleware(JWTAuth)

      resolve(&QueriesResolver.update_query/3)
    end

    @desc ~s"""
    Delete an existing SQL query, identified by the query_id.
    Only the owner of the query can delete it.
    """
    field :delete_sql_query, :sql_query do
      arg(:query_id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&QueriesResolver.delete_query/3)
    end
  end

  object :dashboard_queries do
    @desc ~s"""
    Get a dashboard.
    """
    field :get_dashboard, :dashboard do
      meta(access: :free)
      arg(:id, non_null(:integer))

      resolve(&QueriesResolver.get_dashboard/3)
    end
  end

  object :dashboard_mutations do
    @desc ~s"""
    Create an empty (without queries) dashboard.

    A dashboard is holding together queries, each defining a
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
    field :create_dashboard, :dashboard do
      arg(:name, non_null(:string))
      arg(:description, :string)
      arg(:is_public, :boolean, default_value: false)
      arg(:settings, :json)

      middleware(JWTAuth)

      resolve(&QueriesResolver.create_dashboard/3)
    end

    @desc ~s"""
    Update the name, description, parameters or public status of a dashboard.

    In order to manipulate the panels of the dashboard, refer to the
    createDashboardPanel/updateDashboardPanel/removeDashboardPanel
    mutations.
    """
    field :update_dashboard, :dashboard do
      arg(:id, non_null(:integer))

      arg(:name, :string)
      arg(:description, :string)
      arg(:is_public, :boolean)
      arg(:settings, :json)

      middleware(JWTAuth)

      resolve(&QueriesResolver.update_dashboard/3)
    end

    @desc ~s"""
    Delete a dashboard
    """
    field :delete_dashboard, :dashboard do
      arg(:id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&QueriesResolver.delete_dashboard/3)
    end
  end

  object :dashboard_queries_interaction_mutations do
    @desc ~s"""
    Add a query to a dashboard.

    In order to add a query to a dashboard, the following conditions must be met:
    - The dashboard must exist and must be owned by the querying user;
    - The query must exist and the querying user must have reading access to it (the
      query is public or the querying user owns the query);

    When a query is added to a dashboard, the returned result is a `dashboard_query_mapping`.
    The mapping has its own id, which is used to identify the mapping when updating, deleting
    or running the query. The mapping also has its own settings, which can be used to store
    arbitrary data relevant to the frontend.

    The mapping id is used instead of just the (dashboard_id, query_id) tuple as a single query
    can be added multiple times to a dashboard. It makes sense to add the same query multiple times
    to a dashboard if the global parameters are used to override the query parameters. For example,
    a query can be added to a dashboard with the global parameter `slug` set to `bitcoin`, and then again
    added to the same dashboard with the global parameter `slug` set to `ethereum`. This way, the same
    query can be used to show information about different assets.
    """
    field :create_dashboard_query, :dashboard_query_mapping do
      arg(:dashboard_id, non_null(:integer))
      arg(:query_id, non_null(:integer))

      arg(:settings, :json)

      middleware(JWTAuth)

      resolve(&QueriesResolver.create_dashboard_query/3)
    end

    @desc ~s"""
    Update a dashboard query mapping.

    The dashboard query mapping is identified by the dashboard_id and dashboard_query_mapping_id.
    Only the owner of the dashboard can update the mapping.
    """
    field :update_dashboard_query, :dashboard_query_mapping do
      arg(:dashboard_id, non_null(:integer))
      arg(:dashboard_query_mapping_id, non_null(:integer))
      arg(:settings, :json)

      middleware(JWTAuth)

      resolve(&QueriesResolver.update_dashboard_query/3)
    end

    @desc ~s"""
    Delete a dshboard query mapping.

    The dashboard query mapping is identified by the dashboard_id and dashboard_query_mapping_id.
    Only the owner of the dashboard can delete the mapping.
    """
    field :delete_dashboard_query, :dashboard_query_mapping do
      arg(:dashboard_id, non_null(:integer))
      arg(:dashboard_query_mapping_id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&QueriesResolver.delete_dashboard_query/3)
    end

    @desc ~s"""
    Create a new dashboard global parameter or override the value of an existing one.

    Dashboard global parameters are used to override the query parameters.
    The global parameters are used in two steps:
    - Create a new global parameter with a name and a value via this mutation
    - Override the value of a query parameter with the value of the global parameter
      via the putDashboardGlobalParameterOverride mutation

    When a global parameter is first created it has no effect on any of the queries.
    The overriding needs to be explicitly stated, no automatic overriding based on name is done.
    This allows for more flexibility as it does not put requirements on the parameter names used in
    the queries, which might be owned by other users.
    """
    field :add_dashboard_global_parameter, :dashboard do
      arg(:dashboard_id, non_null(:integer))
      arg(:key, non_null(:string))
      arg(:value, non_null(:dashboard_global_paramter_value))

      middleware(JWTAuth)

      resolve(&QueriesResolver.put_dashboard_global_parameter/3)
    end

    @desc ~s"""
    Create a new dashboard global parameter or override the value of an existing one.

    """

    field :update_dashboard_global_parameter, :dashboard do
      arg(:dashboard_id, non_null(:integer))
      arg(:key, non_null(:string))
      arg(:new_key, :dashboard_global_paramter_value)
      arg(:new_value, :dashboard_global_paramter_value)

      middleware(JWTAuth)

      resolve(&QueriesResolver.put_dashboard_global_parameter/3)
    end

    @desc ~s"""
    Override the value of a query parameter with the value of a global parameter.
    The dashboard and query are identified by the dashboard_id and the dashboard_query_mapping_id.

    The global and local parameters must already exist. The overriding is stored only in the dashboard
    and does not mutate the query itself in any way.

    Only the owner of the dashboard can override the parameters.
    """
    field :put_dashboard_global_parameter_override, :dashboard do
      arg(:dashboard_id, non_null(:integer))
      arg(:dashboard_query_mapping_id, non_null(:integer))

      arg(:global_parameter, non_null(:string))
      arg(:local_parameter, non_null(:string))

      middleware(JWTAuth)

      resolve(&QueriesResolver.put_dashboard_global_parameter_override/3)
    end
  end
end
