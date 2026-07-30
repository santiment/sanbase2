defmodule SanbaseWeb.Graphql.Schema.SignalQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.SignalResolver

  object :signal_queries do
    @desc ~s"""
    Return anomaly events.
    """
    field :get_anomalies, list_of(:anomaly) do
      meta(access: :free)

      arg(:selector, :anomaly_target_selector_input_object)
      arg(:anomalies, list_of(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      cache_resolve(&SignalResolver.get_anomalies/3, ttl: 30, max_ttl_offset: 30)
    end
  end
end
