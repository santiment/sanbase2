defmodule SanbaseWeb.Graphql.MetricTypes do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias Sanbase.Metric

  alias SanbaseWeb.Graphql.Complexity
  alias SanbaseWeb.Graphql.Middlewares.AccessControl
  alias SanbaseWeb.Graphql.Resolvers.MetricResolver

  object :metric_data do
    field(:datetime, non_null(:datetime))
    field(:value, non_null(:float))
  end

  object :histogram_data do
    field(:labels, non_null(list_of(:string)))
    field(:values, non_null(list_of(:float)))
  end

  object :metadata do
    @desc ~s"""
    List of slugs which can be provided to the `timeseriesData` field to fetch
    the metric.
    """
    field :available_slugs, list_of(:string) do
      cache_resolve(&MetricResolver.get_available_slugs/3, ttl: 600)
    end

    @desc ~s"""
    The minimal granularity for which the data is available.
    """
    field(:min_interval, :string)

    @desc ~s"""
    When the interval provided in the query is bigger than `min_interval` and
    contains two or more data points, the data must be aggregated into a single
    data point. The default aggregation that is applied is this `default_aggregation`.
    The default aggregation can be changed by the `aggregation` parameter of
    the `timeseriesData` field. Available aggregations are:
    [
    #{
      (Metric.available_aggregations() -- [nil])
      |> Enum.map(&Atom.to_string/1)
      |> Enum.map(&String.upcase/1)
      |> Enum.join(",")
    }
    ]
    """
    field(:default_aggregation, :aggregation)

    @desc ~s"""
    The supported aggregations for this metric. For more information about
    aggregations see the documentation for `defaultAggregation`
    """
    field(:available_aggregations, list_of(:aggregation))
  end

  object :metric do
    @desc ~s"""
    Return a list of 'datetime' and 'value' for a given metric, slug
    and time period.
    """
    field :timeseries_data, list_of(:metric_data) do
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")
      arg(:aggregation, :aggregation, default_value: nil)

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)

      cache_resolve(&MetricResolver.timeseries_data/3)
    end

    field :histogram_data, :histogram_data do
      arg(:slug, non_null(:string))
      arg(:datetime, non_null(:datetime))

      middleware(AccessControl)

      cache_resolve(&MetricResolver.histogram_data/3)
    end

    field :available_since, :datetime do
      arg(:slug, non_null(:string))
      cache_resolve(&MetricResolver.available_since/3)
    end

    field :metadata, :metadata do
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
