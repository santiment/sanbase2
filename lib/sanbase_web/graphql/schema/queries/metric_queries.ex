defmodule SanbaseWeb.Graphql.Schema.MetricQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.MetricResolver
  alias SanbaseWeb.Graphql.Middlewares.TransformResolution
  alias SanbaseWeb.Graphql.Middlewares.AccessControl

  object :metric_queries do
    @desc ~s"""
    Return data for a given metric.
    """
    field :get_metric, :metric do
      meta(access: :free)
      arg(:metric, non_null(:string))

      middleware(TransformResolution)
      resolve(&MetricResolver.get_metric/3)
    end

    field :get_available_metrics, list_of(:string) do
      meta(access: :free)

      arg(:product, :products_enum, default_value: :sanapi)
      arg(:plan, :plans_enum)
      arg(:has_incomplete_data, :boolean, default_value: nil)

      cache_resolve(&MetricResolver.get_available_metrics/3, ttl: 300)
    end

    field :get_latest_metric_data, list_of(:latest_metric_data) do
      deprecate("""
      This API is not intended for widespread use. \
      It will be deprecated once Websocket Subscriptions are added
      """)

      meta(access: :restricted, min_plan: [sanapi: :pro, sanbase: :pro])

      arg(:selector, :metric_target_selector_input_object)
      arg(:metrics, list_of(:string))

      middleware(AccessControl)
      cache_resolve(&MetricResolver.latest_metrics_data/3, ttl: 30)
    end
  end
end
