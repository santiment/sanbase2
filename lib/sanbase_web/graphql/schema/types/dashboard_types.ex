defmodule SanbaseWeb.Graphql.DashboardTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.{
    DashboardResolver,
    UserResolver,
    VoteResolver
  }

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
  input_object :panel_sql_input_object do
    field(:query, non_null(:string))
    field(:parameters, non_null(:json))
  end

  @desc ~s"""
  Input object for a computed panel.

  A panel obtained via computeDashboardPanel can be
  passed back to the API and store in the cache. The input
  object used when providing that panel result is this.
  """
  input_object :computed_panel_schema_input_object do
    field(:san_query_id, non_null(:string))
    field(:clickhouse_query_id, non_null(:string))
    field(:columns, non_null(list_of(:string)))
    field(:rows, non_null(:json))
    field(:query_start_time, non_null(:datetime))
    field(:query_end_time, non_null(:datetime))
    field(:summary, non_null(:json))
  end

  @desc ~s"""
  Input object for a panel definition (schema).

  This object is used to create a new panel or to
  update an existing panel's definition.
  """
  input_object :panel_schema_input_object do
    field(:name, non_null(:string))
    field(:sql, non_null(:panel_sql_input_object))
    field(:description, :string)
    field(:settings, :json)
  end

  @desc ~s"""
  Describe a clickhouse table structure.

  The description includes about the columns and their types,
  the engine used, the partition and order by expressions.

  The order_by is a list of columns that are used to order the
  data and is of vital importance when the data is queried.
  Filtering of columns that are to the front of the order by
  is much faster than filtering of columns that are not.
  """
  object :clickhouse_table_definition do
    field(:table, non_null(:string))
    field(:description, non_null(:string))
    field(:engine, non_null(:string))
    field(:order_by, non_null(list_of(:string)))
    field(:partition_by, non_null(:string))
    field(:columns, non_null(:json))
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
  object :query_execution_stats do
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
  object :query_result do
    field(:san_query_id, non_null(:string))
    field(:clickhouse_query_id, non_null(:string))
    field(:summary, non_null(:json))
    field(:rows, non_null(:json))
    field(:columns, non_null(list_of(:string)))
    field(:query_start_time, non_null(:datetime))
    field(:query_end_time, non_null(:datetime))
  end

  @desc ~s"""
  Define the Clickhouse SQL query and parameters it takes.

  The query is expected to be a valid SQL query, except for
  the parametrization {{key}} syntax where the {{key}} is the
  name of a key found in the parameters map. When executed,
  the parameters are transformed to positional parameters and
  passed to the query.

  Example:
  query: 'SELECT * FROM table WHERE slug = {{slug}} LIMIT {{limit}}'
  parameters: '{slug: "bitcoin", limit: 10}'
  """
  object :panel_sql do
    field(:query, non_null(:string))
    field(:parameters, non_null(:json))
  end

  @desc ~s"""
  The panel schema describe the definition of a panel -
  its name, type, SQL query, SQL parameters, etc.

  The dashboard schema contains a list of panel schemas,
  ultimately describing the whole dashboard.
  """
  object :panel_schema do
    field(:id, non_null(:string))
    field(:dashboard_id, non_null(:integer))
    field(:string, non_null(:string))
    field(:name, non_null(:string))
    field(:description, :string)
    field(:settings, :json)
    field(:sql, :panel_sql)
  end

  @desc ~s"""
  When a panel is computed, the result can be persisted in
  the database so it can be accessed again without running
  the computation. The Panel Cache represents the result of
  a panel computation. The id is the panel_id as seen in the
  Panel Schema.
  """
  object :panel_cache do
    field(:id, non_null(:string))
    field(:dashboard_id, non_null(:integer))
    field(:san_query_id, non_null(:string))
    field(:clickhouse_query_id, non_null(:string))
    field(:columns, non_null(list_of(:string)))
    field(:rows, non_null(:json))
    field(:query_start_time, :datetime)
    field(:query_end_time, :datetime)
    field(:summary, :json)
    field(:updated_at, non_null(:datetime))
  end

  @desc ~s"""
  The Dashboard Schema defines the dashboard's name, description,
  public status and the list of panel schemas that hold the
  actual Clickhouse SQL query and parameters.
  """
  object :dashboard_schema do
    field(:id, non_null(:integer))
    field(:name, non_null(:string))
    field(:description, :string)
    field(:is_public, non_null(:boolean))
    field(:panels, list_of(:panel_schema))

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

  @desc ~s"""
  This object holds basic information about a stored
  historical dashboard schema - the dashboard id, hash,
  messsage written by the user and time of creation.

  A list of such objects is returned when listing the
  history log of a dashboard. It does not contain details
  like the SQL query, description, etc.
  """
  object :dashboard_schema_history_preview do
    field(:dashboard_id, non_null(:integer))
    field(:hash, :string)
    field(:message, :string)
    field(:inserted_at, :datetime)
  end

  @desc ~s"""
  Describe a past state of a Dashboard Schema.
  This has the same fields as the Dashboard Schema,
  but is extended with a message, hash and inserted_at
  """
  object :dashboard_schema_history do
    field(:message, :string)
    field(:hash, :string)

    field(:dashboard_id, non_null(:integer))
    field(:name, non_null(:string))
    field(:description, :string)
    field(:is_public, non_null(:boolean))
    field(:panels, list_of(:panel_schema))
    field(:inserted_at, :datetime)
  end

  @desc ~s"""
  This object sticks together all the Panel Cache
  objects that are associated with a given dashboard.

  It contains a list of Panel Cache objects, each of which
  holds the result of a panel computation.
  """
  object :dashboard_cache do
    field(:dashboard_id, non_null(:integer))
    field(:panels, list_of(:panel_cache))
  end
end
