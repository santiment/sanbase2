defmodule SanbaseWeb.Graphql.Schema.ChartConfigurationQueries do
  @moduledoc ~s"""
  Queries and mutations for chart configurations.

  Chart configurations are used to store the settings of a chart on sanbase
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.ChartConfigurationResolver
  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

  object :project_chart_queries do
    field :chart_configuration, :chart_configuration do
      meta(access: :free)

      arg(:id, non_null(:integer))

      resolve(&ChartConfigurationResolver.chart_configuration/3)
    end

    field :chart_configurations, list_of(:chart_configuration) do
      meta(access: :free)

      arg(:user_id, :integer)
      arg(:project_id, :integer)
      arg(:project_slug, :string)

      resolve(&ChartConfigurationResolver.chart_configurations/3)
    end
  end

  object :project_chart_mutations do
    field :generate_shared_access_token, :shared_access_token do
      arg(:chart_configuration_id, non_null(:integer))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      middleware(JWTAuth)
      resolve(&ChartConfigurationResolver.generate_shared_access_token/3)
    end

    field :create_chart_configuration, :chart_configuration do
      arg(:settings, non_null(:project_chart_input_object))

      middleware(JWTAuth)
      resolve(&ChartConfigurationResolver.create_chart_configuration/3)
    end

    field :update_chart_configuration, :chart_configuration do
      arg(:id, non_null(:id))
      arg(:settings, non_null(:project_chart_input_object))

      middleware(JWTAuth)
      resolve(&ChartConfigurationResolver.update_chart_configuration/3)
    end

    field :delete_chart_configuration, :chart_configuration do
      arg(:id, non_null(:id))

      middleware(JWTAuth)
      resolve(&ChartConfigurationResolver.delete_chart_configuration/3)
    end
  end
end
