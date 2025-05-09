defmodule SanbaseWeb.Graphql.Schema.QueriesQueries do
  @moduledoc ~s"""
  Queries and mutations for authentication related intercations
  """
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.QueriesResolver
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

      @desc ~s"""
      The id of the user whose queries are being fetched.
      If the argument is not provided, fetch the current user queries.
      """
      arg(:user_id, :integer)

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
    field :get_query_executions, list_of(:sql_query_execution_stats) do
      meta(access: :free)

      arg(:page, non_null(:integer))
      arg(:page_size, non_null(:integer))

      arg(:query_id, :integer)

      middleware(UserAuth)

      resolve(&QueriesResolver.get_query_executions/3)
    end

    @desc ~s"""
    Every SQL query executed in Clickhouse is uniquely identified by an id.

    This unique id is called `clickhouseQueryId` throught our API. If it is
    provided back to thi query by the user that executed it, it returns
    data about the execution of the query - how much RAM memory it used,
    how many gigabytes/rows were read, how big is the result, how much CPU
    time it used, etc.
    """
    field :get_clickhouse_query_execution_stats, :sql_query_execution_stats do
      meta(access: :free)
      arg(:clickhouse_query_id, non_null(:string))

      middleware(JWTAuth)
      resolve(&QueriesResolver.get_clickhouse_query_execution_stats/3)
    end

    @desc ~s"""
    Run the raw Clickhouse SQL query defined by the provided query and parameters.
    The query text is a string and the parameters are a JSON map.
    The query is not stored in the database, and is only executed once.

    Running a query costs credits. The credits cost of a query are computed based
    on how "complex" the query is -- how much data it reads from the disk, how big is
    the result in rows and bytes, how many microseconds of the CPU are used, etc.

    Example:

      {
        runRawSqlQuery(
          sqlQueryText: "SELECT * FROM intraday_metrics WHERE asset_id IN (SELECT asset_id FROM asset_metadata WHERE name = {{slug}}) LIMIT {{limit}}"
          sqlQueryParameters: "{\"slug\": \"bitcoin\", \"limit\": 1}"){
            columns
            rows
            clickhouseQueryId
            creditsCost
        }
      }
    """
    field :run_raw_sql_query, :sql_query_execution_result do
      meta(access: :free)

      arg(:sql_query_text, non_null(:string))
      arg(:sql_query_parameters, non_null(:json), default_value: "{}")

      middleware(UserAuth)

      resolve(&QueriesResolver.run_raw_sql_query/3)
    end

    field :compute_raw_clickhouse_query, :sql_query_execution_result do
      meta(access: :free)
      arg(:query, non_null(:string))
      arg(:parameters, non_null(:json))

      middleware(UserAuth)

      cache_resolve(&QueriesResolver.compute_raw_clickhouse_query/3,
        ttl: 10,
        max_ttl_offset: 10
      )
    end

    @desc ~s"""
    Compute the query asidentified by the id. The query can be computed only if the
    querying user has read access to it (owns the query or the query is public).

    The query is executed with its own set of parameters

    The computed result is not stored in the database.

    Running a query costs credits. The credits cost of a query are computed based
    on how "complex" the query is -- how much data it reads from the disk, how big is
    the result in rows and bytes, how many microseconds of the CPU are used, etc.

    Example:

      {
        runSqlQuery(id: 10){
          columns
          rows
          clickhouseQueryId
          creditsCost
        }
      }
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

    Running a query costs credits. The credits cost of a query are computed based
    on how "complex" the query is -- how much data it reads from the disk, how big is
    the result in rows and bytes, how many microseconds of the CPU are used, etc.

    Example:

      {
        runDashboardSqlQuery(dashboardId: 10, dashboardQueryMappingId: 20){
          columns
          rows
          clickhouseQueryId
          creditsCost
        }
      }
    """
    field :run_dashboard_sql_query, :sql_query_execution_result do
      meta(access: :free)

      arg(:dashboard_id, non_null(:integer))
      arg(:dashboard_query_mapping_id, non_null(:string))

      @desc ~s"""
      A map that contains dashboard global keys as keys and
      a new value as the value.
      When the query is executed, the parameters here override the
      dashboard parameters, allowing anyone to execute the dashboard query
      with modified set of parameters.
      """
      arg(:parameters_override, :json)
      arg(:force_parameters_override, :boolean, default_value: false)

      @desc ~s"""
      If set to true, the execution result is stored in the database.
      The result can be later fetched by the getDashboardCachedQueriesExecutions

      Alongside the cached value, the hash of the SQL query text and the hash
      of the query parameters are also stored.
      """
      arg(:store_execution, :boolean, default_value: false)

      middleware(UserAuth)

      resolve(&QueriesResolver.run_dashboard_sql_query/3)
    end

    @desc ~s"""
    Get metadata bout the Clickhouse database exposed for the SQL Editor.

    The metadata about the Clickhouse database includes information
    about the columns, tables and functions. This information can be used
    for displaying info to user and also in the autocomplete implementation
    """
    field :get_clickhouse_database_metadata, :clickhouse_database_metadata do
      meta(access: :free)

      arg(:functions_filter, :clickhouse_metadata_function_filter_enum)

      cache_resolve(&QueriesResolver.get_clickhouse_database_metadata/3)
    end

    field :generate_title_by_query, :query_human_description do
      meta(access: :free)
      arg(:sql_query_text, non_null(:string))

      middleware(UserAuth)

      resolve(&QueriesResolver.generate_title_by_query/3)
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
        sqlQueryText: "SELECT * FROM intraday_metrics WHERE asset_id = get_asset_id({{slug}}) LIMIT {{limit}}"
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
      arg(:name, non_null(:string))

      arg(:origin_id, :integer)
      arg(:description, :string)
      arg(:is_public, :boolean)
      arg(:sql_query_text, :string)
      arg(:sql_query_parameters, :json)
      arg(:settings, :json)

      middleware(JWTAuth)

      resolve(&QueriesResolver.create_query/3)
    end

    @desc ~s"""
    Update the fields of an existing SQL query, identified by the id.
    Only the owner of the query can update it.

    Example:

    mutation {
      updateSqlQuery(id: 1, sqlQueryParameters: "{\"slug\": \"ethereum\", \"limit\": 1}"){
        id
        name
        description
        isPublic
        sqlQueryText
        sqlQueryParameters
      }
    }
    """
    field :update_sql_query, :sql_query do
      arg(:id, non_null(:integer))

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
    Delete an existing SQL query, identified by the id.
    Only the owner of the query can delete it.

    Example:

      mutation {
        deleteSqlQuery(id: 1){
          id
          name
          description
          isPublic
          sqlQueryText
          sqlQueryParameters
        }
      }
    """
    field :delete_sql_query, :sql_query do
      arg(:id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&QueriesResolver.delete_query/3)
    end

    @desc ~s"""
    Update a dashboard cache for a given query with the provided data.

    The compressed_query_execution_result parameter contains the compressed query result.

    The compressed result is created by taking the JSON representation of the result, gzipping it and
    converting the result with base64 encoding.
    For more information and examples, check here: https://github.com/santiment/sanbase2/pull/3937

    Example:

    mutation {
      storeDashboardQueryExecution(
        dashboardId: 134
        dashboardQueryMappingId: 5
        compressedQueryExecutionResult: "H4sIAAAAAAAAE3WOQWvEIBSE/4tnszyNsdFzW9jDHkrtpUtY3CjdgImp0Zal9L9X08AeSkFkmPfNMF+o9y6Nk7rOdkHyiF72U+QM4Zu419GqYbRZPjqv/5gb2OGtaq3Ry2LjaTD5PtoYhv5Xm5i/D+1SCfZ+nFO05qSLe9axvxQqFxm9XM5eB/OUbLge9DwP09veIDkl5zB6L+7DZNYBElGgdUVIBUIRkLWQdfOKNqqEyKafow7x3wwrmeA/y/wjYS3FhLMGIyLuoIJMEgUg15fJCna0aYELSltRMwLQMnxr5YpwCULSsgS67vsHMa3TkGgBAAA="
        }
      ){
        queries{
          rows
          columns
          queryId
          dashboardQueryMappingId
        }
      }
    }
    """
    field :store_dashboard_query_execution, :dashboard_cached_executions do
      arg(:dashboard_id, non_null(:integer))
      arg(:dashboard_query_mapping_id, non_null(:string))

      @desc ~s"""
      This is the result of the query execution. The JSON obtained from
      runSqlQuery/runRawSqlQuery/runDashboardSqlQuery is first stringified,
      then gzipped and the encoded in base64. This is done to reduce the
      size of the data sent from the frontend to the backend.
      """
      arg(:compressed_query_execution_result, non_null(:string))

      middleware(JWTAuth)

      resolve(&QueriesResolver.cache_dashboard_query_execution/3)
    end

    @desc ~s"""
    Update a query cache for a given user.
    A query can be cached by its owner, as well as by other users, if the query is public.
    After that users can see the owner's cache and their own cache, but not caches of other people.

    The compressed_query_execution_result parameter contains the compressed query result.

    The compressed result is created by taking the JSON representation of the result, gzipping it and
    converting the result with base64 encoding.
    For more information and examples, check here: https://github.com/santiment/sanbase2/pull/3937

    Example:

    mutation {
      storeQueryExecution(
        queryId: 134
      compressedQueryExecutionResult: "The result string of the example above is: H4sIAAAAAAAAE3WOQWvEIBSE/4tnszyNsdFzW9jDHkrtpUtY3CjdgImp0Zal9L9X08AeSkFkmPfNMF+o9y6Nk7rOdkHyiF72U+QM4Zu419GqYbRZPjqv/5gb2OGtaq3Ry2LjaTD5PtoYhv5Xm5i/D+1SCfZ+nFO05qSLe9axvxQqFxm9XM5eB/OUbLge9DwP09veIDkl5zB6L+7DZNYBElGgdUVIBUIRkLWQdfOKNqqEyKafow7x3wwrmeA/y/wjYS3FhLMGIyLuoIJMEgUg15fJCna0aYELSltRMwLQMnxr5YpwCULSsgS67vsHMa3TkGgBAAA=")
    }
    """
    field :store_query_execution, :boolean do
      arg(:query_id, non_null(:integer))

      @desc ~s"""
      This is the result of the query execution. The JSON obtained from
      runSqlQuery/runRawSqlQuery/runDashboardSqlQuery is first stringified,
      then gzipped and the encoded in base64. This is done to reduce the
      size of the data sent from the frontend to the backend.
      """
      arg(:compressed_query_execution_result, non_null(:string))

      middleware(JWTAuth)

      resolve(&QueriesResolver.cache_query_execution/3)
    end
  end

  object :dashboard_queries do
    @desc ~s"""
    Get a dashboard by id.

    If the dashboard is public, everyone can fetch it, and if it is private
    only its owner can fetch it.

    If the dashboard contains private queries, the SQL query text and parameters
    are redacted so they cannot be seen by other people. But the dashboard queries
    can still be executed
    """
    field :get_dashboard, :dashboard do
      meta(access: :free)
      arg(:id, non_null(:integer))

      resolve(&QueriesResolver.get_dashboard/3)
    end

    @desc ~s"""
    Get the last computed version of the queries on a dashboard.

    The query returns a list of the last execution of every
    query. The query execution (cache) is described by its
    id and a JSON-formatted string of the result. The result
    contains the column names, the column types, the rows and
    the time they were computed. The SQL query text and parameters that
    were used to compute the result can be found in the dashhboard
    schema, fetched by the getDashboard query.

    This is called a cache because only the latest result is
    stored and all previous states are discarded. Storing data
    for long time after other computations and changes are done
    is done via snapshots (to be implemented).
    """
    field :get_cached_dashboard_queries_executions, :dashboard_cached_executions do
      meta(access: :free)
      arg(:dashboard_id, non_null(:integer))
      arg(:parameters_override, :json)

      resolve(&QueriesResolver.get_cached_dashboard_queries_executions/3)
    end

    field :get_cached_query_executions, list_of(:query_cached_execution) do
      meta(access: :free)
      arg(:query_id, non_null(:integer))

      resolve(&QueriesResolver.get_cached_query_executions/3)
    end

    @desc ~s"""
    Fetch a list of the dashboards that belong to a user.

    If the querying user is the same as the queried user, both public and private
    dashboards are returned. If the querying user is different from the queried user,
    only the public queries are shown.
    """
    field :get_user_dashboards, list_of(:dashboard_for_lists) do
      meta(access: :free)

      @desc ~s"""
      The id of the user whose queries are being fetched.
      If the argument is not provided, fetch the current user queries.
      """
      arg(:user_id, :integer)

      arg(:page, non_null(:integer))
      arg(:page_size, non_null(:integer))

      resolve(&QueriesResolver.get_user_dashboards/3)
    end
  end

  object :dashboard_mutations do
    @desc ~s"""
    Create an empty (without queries) dashboard.

    A dashboard is holding together queries, each defining a
    Clickhouse SQL query and how to visualize it. The dashboard
    usually has a topic it is about and the queries in it show
    different types of information about that topic.

    The dashboard is created with its name, description, parameters and public
    status. Public dashboards are visible to all users.

    Dashboard holds the global parameters that are shared by all queries
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
      arg(:dashboard_query_mapping_id, non_null(:string))
      # The settings are the only thing that can be updated, hence non_null
      arg(:settings, non_null(:json))

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
      arg(:dashboard_query_mapping_id, non_null(:string))

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

    The parameter key is always a string.
    The parameter value is an input object so the value can have different types. The allowed
    input objects are (and exactly one must be set):
      - value: {string: "santiment"}
      - value: {integer: 3}
      - value: {float: 5.125}
      - value: {stringList: ["bitcoin", "ethereum"]}
      - value: {integerList: [3, 123, 122]}
      - value: {floatList: [5.125, 3.14]}
    Example:
      mutation{
        addDashboardGlobalParameter(dashboardId: 1, key: "slug", value: {string: "bitcoin"}){
          parameters
        }
      }
    """
    field :add_dashboard_global_parameter, :dashboard do
      arg(:dashboard_id, non_null(:integer))
      arg(:key, non_null(:string))
      arg(:value, non_null(:dashboard_global_parameter_value))

      middleware(JWTAuth)

      resolve(&QueriesResolver.add_dashboard_global_parameter/3)
    end

    @desc ~s"""
    Update an existing dashboard global parameter.

    At least one of the new_key and new_value must be provided:
    - new_key - Change the name of the global parameter. Changing the name
      does not require changing the queries and/or the dashboard query mappings.
      The key is used only when displaying the parameter in the frontend;
    - new_value - Change the value of the global parameter.
    """
    field :update_dashboard_global_parameter, :dashboard do
      arg(:dashboard_id, non_null(:integer))
      arg(:key, non_null(:string))
      arg(:new_key, :string)
      arg(:new_value, :dashboard_global_parameter_value)

      middleware(JWTAuth)

      resolve(&QueriesResolver.update_dashboard_global_parameter/3)
    end

    @desc ~s"""
    Delete an existing dashboard global parameter
    """
    field :delete_dashboard_global_parameter, :dashboard do
      arg(:dashboard_id, non_null(:integer))
      arg(:key, non_null(:string))

      middleware(JWTAuth)

      resolve(&QueriesResolver.delete_dashboard_global_parameter/3)
    end

    @desc ~s"""
    Override the value of a query parameter with the value of a global parameter.
    The dashboard and query are identified by the dashboard_id and the dashboard_query_mapping_id.

    The global and local parameters must already exist. The overriding is stored only in the dashboard
    and does not mutate the query itself in any way.

    Only the owner of the dashboard can override the parameters.
    """
    field :add_dashboard_global_parameter_override, :dashboard do
      arg(:dashboard_id, non_null(:integer))
      arg(:dashboard_query_mapping_id, non_null(:string))

      arg(:dashboard_parameter_key, non_null(:string))
      arg(:query_parameter_key, non_null(:string))

      middleware(JWTAuth)

      resolve(&QueriesResolver.add_dashboard_global_parameter_override/3)
    end

    field :delete_dashboard_global_parameter_override, :dashboard do
      arg(:dashboard_id, non_null(:integer))
      arg(:dashboard_query_mapping_id, non_null(:string))

      arg(:dashboard_parameter_key, non_null(:string))

      middleware(JWTAuth)

      resolve(&QueriesResolver.delete_dashboard_global_parameter_override/3)
    end

    # Text Widgets
    field :add_dashboard_text_widget, :dashboard_text_widget_tuple do
      arg(:dashboard_id, non_null(:integer))

      arg(:name, :string)
      arg(:description, :string)
      arg(:body, :string)

      middleware(JWTAuth)

      resolve(&QueriesResolver.add_dashboard_text_widget/3)
    end

    field :update_dashboard_text_widget, :dashboard_text_widget_tuple do
      arg(:dashboard_id, non_null(:integer))
      arg(:text_widget_id, non_null(:string))

      arg(:name, :string)
      arg(:description, :string)
      arg(:body, :string)

      middleware(JWTAuth)

      resolve(&QueriesResolver.update_dashboard_text_widget/3)
    end

    field :delete_dashboard_text_widget, :dashboard_text_widget_tuple do
      arg(:dashboard_id, non_null(:integer))
      arg(:text_widget_id, non_null(:string))

      middleware(JWTAuth)

      resolve(&QueriesResolver.delete_dashboard_text_widget/3)
    end

    # Image Widgets
    field :add_dashboard_image_widget, :dashboard_image_widget_tuple do
      arg(:dashboard_id, non_null(:integer))

      arg(:url, non_null(:string))
      arg(:alt, :string)

      middleware(JWTAuth)

      resolve(&QueriesResolver.add_dashboard_image_widget/3)
    end

    field :update_dashboard_image_widget, :dashboard_image_widget_tuple do
      arg(:dashboard_id, non_null(:integer))
      arg(:image_widget_id, non_null(:string))

      arg(:url, :string)
      arg(:alt, :string)

      middleware(JWTAuth)

      resolve(&QueriesResolver.update_dashboard_image_widget/3)
    end

    field :delete_dashboard_image_widget, :dashboard_image_widget_tuple do
      arg(:dashboard_id, non_null(:integer))
      arg(:image_widget_id, non_null(:string))

      middleware(JWTAuth)

      resolve(&QueriesResolver.delete_dashboard_image_widget/3)
    end

    field :compute_raw_clickhouse_query, :sql_query_execution_result do
      meta(access: :free)
      arg(:query, non_null(:string))
      arg(:parameters, non_null(:json))

      middleware(UserAuth)

      cache_resolve(&QueriesResolver.compute_raw_clickhouse_query/3,
        ttl: 10,
        max_ttl_offset: 10
      )
    end
  end
end
