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
    Fetch a list of the queries that belong to a user.
    If the querying user is the same as the queried user, both public and private
    queries are returned. If the querying user is different from the queried user,
    only the public queries are shown.
    """
    field :get_user_queries, list_of(:clickhouse_sql_query) do
      meta(access: :free)

      arg(:user_id, non_null(:integer))

      arg(:page, non_null(:integer))
      arg(:page_size, non_null(:integer))

      cache_resolve(&QueriesResolver.get_user_queries/3, ttl: 10, max_ttl_offset: 20)
    end

    @desc ~s"""
    Fetch a list of the public queries.
    """
    field :get_public_queries, list_of(:clickhouse_sql_query) do
      meta(access: :free)

      arg(:page, non_null(:integer))
      arg(:page_size, non_null(:integer))

      cache_resolve(&QueriesResolver.get_public_queries/3, ttl: 10, max_ttl_offset: 20)
    end

    @desc ~s"""
    Fetch a list of the queries executions of the current user.

    The list of executions can be additonally filtered by the query_id
    """
    field :get_queries_executions, list_of(:string) do
      meta(access: :free)

      arg(:page, non_null(:integer))
      arg(:page_size, non_null(:integer))

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
        sqlQuery: "SELECT * FROM intraday_metrics WHERE asset_id IN (SELECT asset_id FROM asset_metadata WHERE name = {{slug}}) LIMIT {{limit}}"
        sqlParameters: "{\"slug\": \"bitcoin\", \"limit\": 1}"){
          columns
          rows
      }
    }
    """
    field :run_raw_sql_query, :clickhouse_sql_query_result do
      meta(access: :free)

      arg(:sql_query, non_null(:string))
      arg(:sql_parameters, non_null(:json))

      middleware(UserAuth)

      cache_resolve(&QueriesResolver.run_raw_sql_query/3, ttl: 5, max_ttl_offset: 5)
    end

    @desc ~s"""
    Compute the query asidentified by the query_id. The query can be computed only if the
    querying user has read access to it (owns the query or the query is public).

    The query is executed with its own set of parameters

    The computed result is not stored in the database.
    """
    field :run_sql_query, :clickhouse_sql_query_result do
      meta(access: :free)

      arg(:query_id, non_null(:integer))

      middleware(UserAuth)

      cache_resolve(&QueriesResolver.run_sql_query/3, ttl: 5, max_ttl_offset: 5)
    end

    @desc ~s"""
    Compute the query asidentified by the query_id in the context of dashboard_id.
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
    field :run_dashboard_sql_query, :clickhouse_sql_query_result do
      meta(access: :free)

      arg(:dashboard_query_mapping_id, non_null(:integer))

      middleware(UserAuth)

      cache_resolve(&QueriesResolver.run_dashboard_sql_query/3, ttl: 5, max_ttl_offset: 5)
    end
  end

  object :queries_mutations do
    @desc ~s"""
    TODO
    """
    field :create_sql_query, :clickhouse_sql_query do
      arg(:origin_uuid, :string)
      arg(:name, :string)
      arg(:description, :string)
      arg(:is_public, :boolean)
      arg(:sql_query, :string)
      arg(:sql_parameters, :json)
      arg(:settings, :json)

      middleware(JWTAuth)

      resolve(&QueriesResolver.create_query/3)
    end

    @desc ~s"""
    TODO
    """
    field :update_sql_query, :clickhouse_sql_query do
      arg(:id, non_null(:integer))

      arg(:name, :string)
      arg(:origin_uuid, :string)
      arg(:description, :string)
      arg(:is_public, :boolean)
      arg(:sql_query, :string)
      arg(:sql_parameters, :json)
      arg(:settings, :json)

      middleware(JWTAuth)

      resolve(&QueriesResolver.update_query/3)
    end

    @desc ~s"""
    TODO
    """
    field :delete_sql_query, :clickhouse_sql_query do
      arg(:id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&QueriesResolver.delete_query/3)
    end

    @desc ~s"""
    TODO
    """
    field :add_dashboard_query, :dashboard_query_mapping do
      arg(:dashboard_id, non_null(:integer))
      arg(:query_id, non_null(:integer))
      arg(:settings, :json)

      middleware(JWTAuth)

      resolve(&QueriesResolver.add_query_to_dashboard/3)
    end

    @desc ~s"""
    TODO
    """
    field :update_dashboard_query, :dashboard_query_mapping do
      arg(:dashboard_id, non_null(:integer))
      arg(:dashboarD_query_mapping_id, non_null(:integer))
      arg(:settings, :json)

      middleware(JWTAuth)

      resolve(&QueriesResolver.update_dashboard_query_mapping/3)
    end

    @desc ~s"""
    TODO
    """
    field :remove_dashboard_query, :dashboard_query_mapping do
      arg(:dashboard_id, non_null(:integer))
      arg(:dashboarD_query_mapping_id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&QueriesResolver.remove_query_from_dashboard/3)
    end
  end
end
