defmodule SanbaseWeb.Graphql.QueriesTypes do
  use Absinthe.Schema.Notation
  alias SanbaseWeb.Graphql.Resolvers.UserResolver
  alias SanbaseWeb.Graphql.Resolvers.VoteResolver
  alias SanbaseWeb.Graphql.Resolvers.DashboardResolver

  @desc ~s"""
  A GraphQL type that represents an SQL Query.

  The SQL Query is an entity that encapsulates a Clickhouse SQL query, the
  query parameters and the query metadata (name, description, etc.).

  The query can be public or private. Public queries are visible to all users,
  while private queries are visible only to the user that created them.
  Queries can be executed and the result of their executions displayed.
  """
  object :sql_query do
    # Identification data
    field(:id, non_null(:integer))
    field(:uuid, non_null(:string))
    field(:origin_id, :integer)

    # Basic Info
    field(:name, non_null(:string))
    field(:description, non_null(:string))
    field(:is_public, non_null(:boolean))
    field(:settings, non_null(:json))

    # SQL Query & Params
    field(:sql_query_text, non_null(:string))
    field(:sql_query_parameters, non_null(:json))

    # User
    field(:user, :user)

    # Cached value. Store the last run of the query along with
    # some metadata - when it was computed, how long it took, etc.
    # field(:last_known_result, :sql_query_execution_result)

    # Votes
    field :votes, :vote do
      resolve(&VoteResolver.votes/3)
    end

    field :voted_at, :datetime do
      resolve(&VoteResolver.voted_at/3)
    end

    # Timestamps
    field(:created_at, non_null(:datetime))
    field(:updated_at, non_null(:datetime))
  end

  object :text_widget do
    field(:id, non_null(:string))
    field(:name, :string)
    field(:description, :string)
    field(:body, :string)

    # Timestamps
    field(:created_at, non_null(:datetime))
    field(:updated_at, non_null(:datetime))
  end

  @desc ~s"""
  The Dashboard type defines the Queries 2.0 dashboard -- it holds the static data
  (name, description, public status, owner, etc.), and the list of queries that hold the
  actual SQL Query and parameters. The result of the execution of the
  SQL query is not part of the dashboard definition.

  Some of the fields are virtual (views), or computed on-the-fly and not stored
  in the dashboard itself -- the comments, votes, if the dashboard is
  featured.

  The Dashboard :parameters field is used to define global parameters that can override
  the query's own parameters. The interaction with the global parameter happens through the
  putDashboardGlobalParameter and putDashboardGlobalParameterOverride mutations.
  """
  object :dashboard do
    field(:id, non_null(:integer))
    field(:name, non_null(:string))
    field(:is_public, non_null(:boolean))
    field(:description, :string)
    field(:parameters, :json)
    field(:settings, :json)

    # Virtual view field
    field(:views, :integer)

    # Old: Panels. This is going to be deprecated
    # in Queries 2.0 in favor of the new :queries field.
    # This is kept for backwards compatibility.
    field :panels, list_of(:panel_schema) do
      resolve(fn root, _, _ ->
        {:ok, root.panels || []}
      end)
    end

    # New: Queries. This is replacing the :panels
    # list from Queries 1.0
    field(:queries, list_of(:sql_query))

    field(:text_widgets, list_of(:text_widget))

    field :user, non_null(:public_user) do
      resolve(&UserResolver.user_no_preloads/3)
    end

    field :comments_count, :integer do
      resolve(&DashboardResolver.comments_count/3)
    end

    field :voted_at, :datetime do
      resolve(&VoteResolver.voted_at/3)
    end

    field :votes, :vote do
      resolve(&VoteResolver.votes/3)
    end

    field(:inserted_at, :datetime)
    field(:updated_at, :datetime)
  end

  object :dashboard_for_lists do
    # Do not allow fetching queries/panels when a list
    # of dashboards is used.

    field(:id, non_null(:integer))
    field(:name, non_null(:string))
    field(:is_public, non_null(:boolean))
    field(:description, :string)
    field(:parameters, :json)
    field(:settings, :json)

    # Virtual view field
    field(:views, :integer)

    field :user, non_null(:public_user) do
      resolve(&UserResolver.user_no_preloads/3)
    end

    field :comments_count, :integer do
      resolve(&DashboardResolver.comments_count/3)
    end

    field :voted_at, :datetime do
      resolve(&VoteResolver.voted_at/3)
    end

    field :votes, :vote do
      resolve(&VoteResolver.votes/3)
    end

    field(:inserted_at, :datetime)
    field(:updated_at, :datetime)
  end

  input_object :dashboard_global_parameter_value do
    field(:boolean, :boolean)
    field(:integer, :integer)
    field(:integer_list, list_of(:integer))
    field(:float, :float)
    field(:float_list, list_of(:float))
    field(:string, :string)
    field(:string_list, list_of(:string))
  end

  @desc ~s"""
  Get memory/duration/credits/etc. details about an
  executed clickhouse query.

  Every computation (from a panel or a raw query) generates
  a clickhouse_query_id that uniquly identifies that exact
  query run. It can be used to get the details about a
  query execution - how much memory it used, how long it run,
  how many credits were spent running this query, etc.
  """
  object :sql_query_execution_stats do
    field(:query_id, :integer)
    field(:read_compressed_gb, non_null(:float))
    field(:cpu_time_microseconds, non_null(:float))
    field(:query_duration_ms, non_null(:float))
    field(:memory_usage_gb, non_null(:float))
    field(:read_rows, non_null(:float))
    field(:read_gb, non_null(:float))
    field(:result_rows, non_null(:float))
    field(:result_gb, non_null(:float))
    field(:credits_cost, non_null(:float))
    field(:query_start_time, non_null(:datetime))
    field(:query_end_time, non_null(:datetime))
    field(:inserted_at, non_null(:datetime))
  end

  @desc ~s"""
  The result of executing a raw Clickhouse SQL query.

  The field interpration is as follows:
  - columns: A list of column names returned by the query, in
    the order specified by the query
  - columnTypes: A list of Clickhouse column types, in the
    order specified by the query
  - rows: A list of lists, where each list is a row of the
    result set.
  - clickhouseQueryId: A unique identifier for the query
    execution, generated by the database during execution.
    This can be used to get the details about the query execution.
  - summary: A JSON containing a subset of the query execution
    details that are available at the time of the executions.
    Not all execution details are available at this point. To get
    all the execution details, provide the clickhouseQueryId to the
    getQueryExecutionStats query.
  - queryStartTime: The time when the query started executing.
  - queryEndTime: The time when the query finished executing.
  """
  object :sql_query_execution_result do
    field(:clickhouse_query_id, non_null(:string))
    field(:summary, non_null(:json))
    field(:rows, non_null(:json))
    field(:columns, non_null(list_of(:string)))
    field(:column_types, non_null(list_of(:string)))
    field(:query_start_time, non_null(:datetime))
    field(:query_end_time, non_null(:datetime))
  end

  object :dashboard_query_mapping do
    field(:id, non_null(:string))
    field(:query, non_null(:sql_query))
    field(:dashboard, non_null(:dashboard))
    field(:settings, :json)
  end

  object :dashboard_text_widget_tuple do
    field(:text_widget, non_null(:text_widget))
    field(:dashboard, non_null(:dashboard))
  end
end
