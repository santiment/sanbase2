defmodule SanbaseWeb.Graphql.Schema.MetricQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.MetricResolver
  alias SanbaseWeb.Graphql.Complexity
  alias SanbaseWeb.Graphql.Middlewares.TimeframeRestriction

  object :metric_queries do
    @desc "Returns a list of slugs of the projects that have a github link"
    field :get_timeseries_metric, list_of(:metric) do
      meta(subscription: :custom_access)

      arg(:metric, non_null(:string))
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1d")
      arg(:aggregation, :aggregation, default_value: nil)

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction)

      cache_resolve(&MetricResolver.get_timeseries_metric/3)
    end
  end
end
