defmodule SanbaseWeb.Graphql.EcosystemTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.EcosystemResolver

  object :ecosystem_metric_data do
    field(:datetime, non_null(:datetime))
    field(:value, non_null(:float))
  end

  object :ecosystem do
    field(:name, non_null(:string))
    field(:projects, list_of(:project))

    field :aggregated_timeseries_data, non_null(:float) do
      arg(:metric, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:aggregation, :aggregation, default_value: nil)

      resolve(&EcosystemResolver.aggregated_timeseries_data/3)
    end

    field :timeseries_data, list_of(:ecosystem_metric_data) do
      arg(:metric, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, non_null(:interval))
      arg(:aggregation, :aggregation, default_value: nil)
      arg(:transform, :timeseries_metric_transform_input_object)

      resolve(&EcosystemResolver.timeseries_data/3)
    end
  end
end
