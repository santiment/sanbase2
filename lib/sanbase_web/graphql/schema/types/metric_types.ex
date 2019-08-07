defmodule SanbaseWeb.Graphql.MetricTypes do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Complexity
  alias SanbaseWeb.Graphql.Middlewares.TimeframeRestriction
  alias SanbaseWeb.Graphql.Resolvers.MetricResolver

  object :metric_data do
    field(:datetime, non_null(:datetime))
    field(:value, non_null(:float))
  end

  object :metadata do
    field(:min_interval, :string)
    field(:default_aggregation, :aggregation)
  end

  object :metric do
    @desc ~s"""
    Return a list of 'datetime',  float 'value' for a given metric, slug
    and time period
    """
    field :timeseries_data, list_of(:metric_data) do
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1d")
      arg(:aggregation, :aggregation, default_value: nil)

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction)

      cache_resolve(&MetricResolver.get_timeseries_data/3)
    end

    field :metadata, list_of(:metadata) do
      cache_resolve(&MetricResolver.get_metadata/3)
    end
  end

  enum :aggregation do
    value(:any)
    value(:last)
    value(:first)
    value(:avg)
    value(:sum)
    value(:min)
    value(:max)
    value(:median)
  end
end
