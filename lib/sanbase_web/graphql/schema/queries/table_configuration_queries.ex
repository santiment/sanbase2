defmodule SanbaseWeb.Graphql.Schema.TableConfigurationQueries do
  @moduledoc ~s"""
  Queries and mutations for chart configurations.

  Chart configurations are used to store the settings of a chart on sanbase
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Middlewares.JWTAuth
  alias SanbaseWeb.Graphql.Resolvers.TableConfigurationResolver

  object :table_configuration_queries do
    field :table_configuration, :table_configuration do
      meta(access: :free)

      arg(:id, non_null(:integer))

      resolve(&TableConfigurationResolver.table_configuration/3)
    end

    field :table_configurations, list_of(:table_configuration) do
      meta(access: :free)

      arg(:user_id, :integer)
      arg(:project_id, :integer)

      resolve(&TableConfigurationResolver.table_configurations/3)
    end
  end

  object :table_configuration_mutations do
    field :create_table_configuration, :table_configuration do
      arg(:settings, non_null(:table_configuration_input_object))

      middleware(JWTAuth)
      resolve(&TableConfigurationResolver.create_table_configuration/3)
    end

    field :update_table_configuration, :table_configuration do
      arg(:id, non_null(:id))
      arg(:settings, non_null(:table_configuration_input_object))

      middleware(JWTAuth)
      resolve(&TableConfigurationResolver.update_table_configuration/3)
    end

    field :delete_table_configuration, :table_configuration do
      arg(:id, non_null(:id))

      middleware(JWTAuth)
      resolve(&TableConfigurationResolver.delete_table_configuration/3)
    end
  end
end
