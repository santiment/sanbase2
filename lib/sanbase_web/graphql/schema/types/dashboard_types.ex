defmodule SanbaseWeb.Graphql.DashboardTypes do
  use Absinthe.Schema.Notation

  input_object :panel_sql_input_object do
    field(:query, non_null(:string))
    field(:args, non_null(:json))
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
    field(:args, non_null(:json))
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
    field(:panel_id, non_null(:string))
    field(:data, non_null(:json))
    field(:updated_at, non_null(:datetime))
  end

  object :dashboard_schema do
    field(:id, non_null(:integer))
    field(:name, non_null(:string))
    field(:description, :string)
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
