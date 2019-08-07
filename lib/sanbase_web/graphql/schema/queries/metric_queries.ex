defmodule SanbaseWeb.Graphql.Schema.MetricQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.MetricResolver

  object :metric_queries do
    @desc ~s"""
    Return data for a given metric.
    """
    field :get_metric, list_of(:metric) do
      meta(access: :restricted)
      arg(:metric, non_null(:string))
      cache_resolve(&MetricResolver.get_metric/3)
    end

    field :get_available_metrics, list_of(:string) do
      meta(access: :free)
      cache_resolve(&MetricResolver.get_available_metrics/3, ttl: 600)
    end

    field :get_available_slugs, list_of(:string) do
      meta(access: :free)
      resolve(&MetricResolver.get_available_metrics/3)
    end
  end
end
