defmodule SanbaseWeb.Graphql.QueriesTypes do
  use Absinthe.Schema.Notation

  object :clickhouse_sql_query do
    # Identification data
    field(:id, non_null(:integer))
    field(:uuid, non_null(:string))
    field(:origin_uuid, non_null(:string))

    # Basic Info
    field(:name, non_null(:string))
    field(:description, non_null(:string))
    field(:is_public, non_null(:boolean))
    field(:settings, non_null(:json))

    # SQL Query & Params
    field(:sql_query, non_null(:string))
    field(:sql_parameters, non_null(:json))

    # Cached value. Store the last run of the query along with
    # some metadata - when it was computed, how long it took, etc.
    field(:last_known_result, :clickhouse_sql_query_result)

    # Timestamps
    field(:created_at, non_null(:datetime))
    field(:updated_at, non_null(:datetime))
  end

  @desc ~s"""
  Input object for an SQL query and its parameters.

  The SQL query is expected to be a valid SQL query.
  The parametrization is done via the {{key}} syntax
  where the {{key}} is the name of the parameter and when
  the query is computed, the key is substituted for the
  value provided in `parameters`.
  The parameters are a JSON map where the key is the
  parameter name and the value is its value.

  Example:
  query: 'SELECT * FROM table WHERE slug = {{slug}} LIMIT {{limit}}'
  parameters: '{slug: "bitcoin", limit: 10}'
  """
  input_object :sql_query_input_object do
    field(:sql_query, :string)
    field(:sql_parameters, :json)

    field(:name, :string)
    field(:description, :string)
    field(:is_public, :boolean)
    field(:settings, :json)
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
  """
  object :clickhouse_sql_query_result do
    field(:clickhouse_query_id, non_null(:string))
    field(:summary, non_null(:json))
    field(:rows, non_null(:json))
    field(:columns, non_null(list_of(:string)))
    field(:column_types, non_null(list_of(:string)))
    field(:query_start_time, non_null(:datetime))
    field(:query_end_time, non_null(:datetime))
  end

  @desc ~s"""
  The Dashboard Schema defines the dashboard's name, description,
  public status and the list of panel schemas that hold the
  actual Clickhouse SQL query and parameters.
  """
  object :dashboard do
    field(:id, non_null(:integer))
    field(:name, non_null(:string))
    field(:description, :string)
    field(:is_public, non_null(:boolean))
    field(:queries, list_of(:clickhouse_sql_query))
    field(:parameters, non_null(:json))
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

  object :dashboard_query_mapping do
    field(:id, non_null(:integer))
    field(:query, non_null(:clickhouse_sql_query))
    field(:dashboard, non_null(:dashboard))
  end
end
