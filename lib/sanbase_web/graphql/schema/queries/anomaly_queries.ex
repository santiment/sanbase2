defmodule SanbaseWeb.Graphql.Schema.AnomalyQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.AnomalyResolver
  alias SanbaseWeb.Graphql.Middlewares.TransformResolution

  object :anomaly_queries do
    @desc ~s"""
    Return data for a given metric.
    """
    field :get_anomaly, :anomaly do
      meta(access: :free)
      arg(:anomaly, non_null(:string))

      middleware(TransformResolution)
      resolve(&AnomalyResolver.get_anomaly/3)
    end

    field :get_available_anomalies, list_of(:string) do
      meta(access: :free)
      cache_resolve(&AnomalyResolver.get_available_anomalies/3, ttl: 600)
    end
  end
end
