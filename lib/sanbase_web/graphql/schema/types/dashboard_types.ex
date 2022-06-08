defmodule SanbaseWeb.Graphql.DashboardTypes do
  use Absinthe.Schema.Notation

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

  enum :panel_type do
    value(:chart)
    value(:type)
  end

  input_object :panel_input_object do
    field(:name, non_null(:string))
    field(:type, :panel_type)
    field(:sql, non_null(:panel_sql_input_object))

    field(:description, :string)
    field(:position, :json)
    field(:size, :json)
  end

  object :panel_sql do
    field(:query, non_null(:string))
    field(:parameters, non_null(:json))
  end

  object :panel_schema do
    field(:id, non_null(:string))
    field(:dashboard_id, non_null(:integer))
    field(:string, non_null(:string))
    field(:name, non_null(:string))
    field(:type, non_null(:string))
    field(:description, :string)
    field(:position, :json)
    field(:size, :json)
    field(:sql, :panel_sql)
  end

  object :panel_cache do
    field(:id, non_null(:string))
    field(:dashboard_id, non_null(:integer))
    field(:san_query_id, non_null(:string))
    field(:clickhouse_query_id, non_null(:string))
    field(:column_names, non_null(list_of(:string)))
    field(:rows, non_null(:json))
    field(:query_start_time, :datetime)
    field(:query_end_time, :datetime)
    field(:summary, :json)
    field(:updated_at, non_null(:datetime))
  end

  object :dashboard_schema do
    field(:id, non_null(:integer))
    field(:name, non_null(:string))
    field(:description, :string)
    field(:is_public, non_null(:boolean))
    field(:panels, list_of(:panel_schema))

    field :user, non_null(:public_user) do
      resolve(&SanbaseWeb.Graphql.Resolvers.UserResolver.user_no_preloads/3)
    end
  end

  object :dashboard_cache do
    field(:dashboard_id, non_null(:integer))
    field(:panels, list_of(:panel_cache))
  end
end
