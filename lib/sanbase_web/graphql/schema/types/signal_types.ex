defmodule SanbaseWeb.Graphql.SignalTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias Sanbase.Signal
  alias SanbaseWeb.Graphql.Complexity
  alias SanbaseWeb.Graphql.Middlewares.AccessControl
  alias SanbaseWeb.Graphql.Resolvers.SignalResolver

  input_object :signal_selector_input_object do
    field(:slug, :string)
    field(:slugs, list_of(:string))
  end

  input_object :signal_target_selector_input_object do
    field(:slug, :string)
    field(:slugs, list_of(:string))
    field(:market_segments, list_of(:string))
    field(:ignored_slugs, list_of(:string))
    field(:watchlist_id, :integer)
    field(:watchlist_slug, :string)
  end

  object :raw_signal do
    field(:signal, non_null(:string))
    field(:is_hidden, non_null(:boolean))
    field(:datetime, :datetime)
    field(:slug, :string)
    field(:value, :float)
    field(:metadata, :json)

    # The signals can be computed for assets that are no longer linked to
    # an existing project. In this case this field can be nil.
    field :project, :project do
      cache_resolve(&SignalResolver.project/3)
    end
  end

  object :signal_data do
    field(:datetime, non_null(:datetime))
    field(:value, :float)
    field(:metadata, list_of(:json))
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
    When the interval provided in the query is bigger than `min_interval` and
    contains two or more data points, the data must be aggregated into a single
    data point. The default aggregation that is applied is this `default_aggregation`.
    The default aggregation can be changed by the `aggregation` parameter of
    the `timeseriesData` field. Available aggregations are:
    [
    #{Signal.available_aggregations() |> Enum.map(&Atom.to_string/1) |> Enum.map_join(",", &String.upcase/1)}
    ]
    """
    field(:default_aggregation, :aggregation)

    @desc ~s"""
    The supported aggregations for this signal. For more information about
    aggregations see the documentation for `defaultAggregation`
    """
    field(:available_aggregations, list_of(:aggregation))
    field(:data_type, :signal_data_type)
    field(:is_accessible, :boolean)
    field(:is_restricted, :boolean)
    field(:restricted_from, :datetime)
    field(:restricted_to, :datetime)
  end

  object :signal do
    @desc ~s"""
    Return a list of 'datetime' and 'value' for a given anomaly, slug
    and time period.
    """
    field :timeseries_data, list_of(:signal_data) do
      arg(:slug, :string)
      arg(:selector, :signal_selector_input_object)
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")
      arg(:aggregation, :aggregation, default_value: nil)

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl, %{allow_realtime_data: true, allow_historical_data: true})

      cache_resolve(&SignalResolver.timeseries_data/3)
    end

    @desc ~s"""
    A derivative of the `timeseriesData` - read its full descriptio if not
    familiar with it.

    `aggregatedTimeseriesData` returns a single float value instead of list
    of datetimes and values. The single values is computed by aggregating all
    of the values in the specified from-to range with the `aggregation` aggregation.
    """
    field :aggregated_timeseries_data, :float do
      arg(:slug, :string)
      arg(:selector, :signal_selector_input_object)
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:aggregation, :aggregation, default_value: nil)

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)

      cache_resolve(&SignalResolver.aggregated_timeseries_data/3)
    end

    field :available_since, :datetime do
      arg(:slug, :string)
      arg(:selector, :signal_selector_input_object)
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
