defmodule SanbaseWeb.Graphql.SignalTypes do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias SanbaseWeb.Graphql.Complexity
  alias SanbaseWeb.Graphql.Middlewares.AccessControl
  alias SanbaseWeb.Graphql.Resolvers.SignalResolver
  alias Sanbase.Signal

  object :signal_data do
    field(:datetime, non_null(:datetime))
    field(:value, :float)
  end

  object :signal_metadata do
    @desc ~s"""
    The name of the signal the metadata is about
    """
    field(:signal, non_null(:string))

    @desc ~s"""
    List of slugs which can be provided to the `timeseriesData` field to fetch
    the signal.
    """
    field :available_slugs, list_of(:string) do
      cache_resolve(&SignalResolver.get_available_slugs/3, ttl: 600)
    end

    @desc ~s"""
    The minimal granularity for which the data is available.
    """
    field(:min_interval, :string)

    @desc ~s"""
    The metric for which the anomaly is about. The actual metric values can be
    fetched via the `getMetric` API using the same metric as argument
    """
    field(:metric, :string)

    @desc ~s"""
    When the interval provided in the query is bigger than `min_interval` and
    contains two or more data points, the data must be aggregated into a single
    data point. The default aggregation that is applied is this `default_aggregation`.
    The default aggregation can be changed by the `aggregation` parameter of
    the `timeseriesData` field. Available aggregations are:
    [
    #{
      Signal.available_aggregations()
      |> Enum.map(&Atom.to_string/1)
      |> Enum.map(&String.upcase/1)
      |> Enum.join(",")
    }
    ]
    """
    field(:default_aggregation, :aggregation)

    @desc ~s"""
    The supported aggregations for this anomaly. For more information about
    aggregations see the documentation for `defaultAggregation`
    """
    field(:available_aggregations, list_of(:aggregation))

    field(:data_type, :signal_data_type)
  end

  object :signal do
    @desc ~s"""
    Return a list of 'datetime' and 'value' for a given anomaly, slug
    and time period.
    """
    field :timeseries_data, list_of(:signal_data) do
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")
      arg(:aggregation, :aggregation, default_value: nil)

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl, %{allow_realtime_data: true, allow_historical_data: true})

      cache_resolve(&SignalResolver.timeseries_data/3)
    end

    field :available_since, :datetime do
      arg(:slug, non_null(:string))
      cache_resolve(&SignalResolver.available_since/3)
    end

    field :metadata, :signal_metadata do
      cache_resolve(&SignalResolver.get_metadata/3)
    end
  end

  enum :signal_data_type do
    value(:timeseries)
  end
end
