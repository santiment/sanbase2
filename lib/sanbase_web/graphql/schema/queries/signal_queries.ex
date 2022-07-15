defmodule SanbaseWeb.Graphql.Schema.SignalQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.SignalResolver
  alias SanbaseWeb.Graphql.Middlewares.TransformResolution

  object :signal_queries do
    @desc ~s"""
    Return data for a given metric.
    """
    field :get_signal, :signal do
      meta(access: :free)
      arg(:signal, non_null(:string))

      middleware(TransformResolution)
      resolve(&SignalResolver.get_signal/3)
    end

    field :get_available_signals, list_of(:string) do
      meta(access: :free)
      cache_resolve(&SignalResolver.get_available_signals/3, ttl: 120)
    end

    field :get_raw_signals, list_of(:raw_signal) do
      meta(access: :free)

      arg(:selector, :signal_target_selector_input_object)
      arg(:signals, list_of(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      cache_resolve(&SignalResolver.get_raw_signals/3, ttl: 30, max_ttl_offset: 30)
    end
  end
end
