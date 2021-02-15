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
      cache_resolve(&SignalResolver.get_available_signals/3, ttl: 600)
    end
  end
end
