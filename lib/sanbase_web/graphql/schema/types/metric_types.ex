defmodule SanbaseWeb.Graphql.MetricTypes do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias SanbaseWeb.Graphql.Complexity
  alias SanbaseWeb.Graphql.Middlewares.AccessControl
  alias SanbaseWeb.Graphql.Resolvers.MetricResolver

  enum :products_enum do
    value(:sanapi)
    value(:sanbase)
  end

  enum :plans_enum do
    value(:free)
    value(:basic)
    value(:pro)
    value(:custom)
  end

  enum :selector_name do
    # common
    value(:blockchain)
    # blockchain address related
    value(:blockchain_address)
    # project related
    value(:slug)
    value(:slugs)
    value(:ignored_slugs)
    value(:market_segments)
    value(:contract_address)
    value(:contract_address_raw)
    # watchlist related
    value(:watchlist_slug)
    value(:watchlist_id)
    # social related
    value(:text)
    value(:source)
    # label related
    value(:owner)
    value(:owners)
    value(:label)
    value(:labels)
    value(:label_fqn)
    value(:label_fqns)
    value(:holders_count)
    # dev activity related
    value(:organization)
    value(:organizations)
    # cache-controling
    value(:base_ttl)
    value(:max_ttl_offset)
  end

  input_object :caching_params_input_object do
    field(:base_ttl, :integer)
    field(:max_ttl_offset, :integer)
  end

  input_object :metric_target_selector_input_object do
    # common
    field(:blockchain, :string)
    # blockchain address related
    field(:blockchain_address, :blockchain_address_selector_input_object)
    # project related
    field(:slug, :string)
    field(:slugs, list_of(:string))
    field(:market_segments, list_of(:string))
    field(:contract_address, :string)
    field(:ignored_slugs, list_of(:string))
    # watchlist related
    field(:watchlist_id, :integer)
    field(:watchlist_slug, :string)
    # social related
    field(:text, :string)
    field(:source, :string)
    # dev activity related
    field(:organization, :string)
    field(:organizations, list_of(:string))
    # label related
    field(:owner, :string)
    field(:owners, list_of(:string))
    field(:label, :string)
    field(:labels, list_of(:string))
    field(:label_fqn, :string)
    field(:label_fqns, list_of(:string))
    field(:holders_count, :integer)

    # contract address not transformed to slug selector
    field(:contract_address_raw, :string)
  end

  input_object :timeseries_metric_transform_input_object do
    field(:type, non_null(:string))
    field(:moving_average_base, :integer)
  end

  enum :metric_data_type do
    value(:timeseries)
    value(:histogram)
    value(:table)
  end

  object :broken_data do
    field(:from, non_null(:datetime))
    field(:to, non_null(:datetime))
    field(:what, non_null(:string))
    field(:why, non_null(:string))
    field(:notes, non_null(:string))
    field(:actions_to_fix, non_null(:string))
  end

  object :metric_data do
    field(:datetime, non_null(:datetime))
    field(:value, :float)
    field(:value_ohlc, :ohlc_data)
  end

  object :latest_metric_data do
    field(:slug, :string)
    field(:metric, :string)
    field(:value, :float)
    field(:datetime, :datetime)
    field(:computed_at, :datetime)
  end

  object :ohlc_data do
    field(:open, :float)
    field(:close, :float)
    field(:high, :float)
    field(:low, :float)
  end

  object :slug_float_value_pair do
    field(:slug, non_null(:string))
    field(:value, :float)
  end

  object :metric_data_per_slug do
    field(:datetime, non_null(:datetime))
    field(:data, list_of(:slug_float_value_pair))
  end

  object :string_list do
    field(:data, list_of(:string))
  end

  object :float_list do
    field(:data, list_of(:float))
  end

  object :float_range_float_value_list do
    field(:data, list_of(:float_range_float_value))
  end

  object :float_range_float_value do
    field(:range, list_of(:float))
    field(:value, :float)
  end

  object :object_address_float_value do
    field(:address, :address)
    field(:value, :float)
  end

  object :string_address_float_value do
    field(:address, :string)
    field(:balance, :float)
    field(:labels, list_of(:string))
    field(:value, :float)
  end

  object :datetime_range_float_value do
    field(:range, list_of(:datetime))
    field(:value, :float)
  end

  object :string_label_float_value do
    field(:label, :string)
    field(:value, :float)
  end

  object :string_address_string_label_float_value do
    field(:address, :string)
    field(:label, :string)
    field(:value, :float)
  end

  # List objects
  object :string_address_float_value_list do
    field(:data, list_of(:string_address_float_value))
  end

  object :object_address_float_value_list do
    field(:data, list_of(:string_address_float_value))
  end

  object :datetime_range_float_value_list do
    field(:data, list_of(:datetime_range_float_value))
  end

  object :string_label_float_value_list do
    field(:data, list_of(:string_label_float_value))
  end

  object :string_address_string_label_float_value_list do
    field(:data, list_of(:string_address_string_label_float_value))
  end

  union :value_list do
    description("Type Parameterized Array")

    types([
      :string_list,
      :float_list,
      :float_range_float_value_list,
      :datetime_range_float_value_list,
      :string_address_float_value_list,
      :string_label_float_value_list,
      :string_address_string_label_float_value_list
    ])

    resolve_type(fn
      %{data: [value | _]}, _ when is_number(value) ->
        :float_list

      %{data: [value | _]}, _ when is_binary(value) ->
        :string_list

      %{data: [%{range: [r | _], value: value} | _]}, _
      when is_number(r) and is_number(value) ->
        :float_range_float_value_list

      %{data: [%{range: [%DateTime{} | _], value: value} | _]}, _ when is_number(value) ->
        :datetime_range_float_value_list

      %{data: [%{address: address, label: label, value: value} | _]}, _
      when is_binary(label) and is_binary(address) and is_number(value) ->
        :string_address_string_label_float_value_list

      %{data: [%{address: address, value: value} | _]}, _
      when is_binary(address) and is_number(value) ->
        :string_address_float_value_list

      %{data: [%{label: label, value: value} | _]}, _
      when is_binary(label) and is_number(value) ->
        :string_label_float_value_list

      %{data: []}, _ ->
        :float_list
    end)
  end

  object :histogram_data do
    field(:labels, list_of(:string))
    field(:values, :value_list)
  end

  object :table_data do
    field(:rows, list_of(:string))
    field(:columns, list_of(:string))
    field(:values, list_of(list_of(:float)))
  end

  object :metric_metadata do
    @desc ~s"""
    The name of the metric the metadata is about
    """
    field(:metric, non_null(:string))

    @desc ~s"""
    A human readable name of the metric.
    For example the human readable name of `mvrv_usd_5y` is `MVRV for coins that moved in the past 5 years`
    """
    field :human_readable_name, non_null(:string) do
      cache_resolve(&MetricResolver.get_human_readable_name/3, ttl: 3600)
    end

    @desc ~s"""
    List of slugs which can be provided to the `timeseriesData` field to fetch
    the metric.
    """
    field :available_slugs, list_of(:string) do
      arg(:selector, :aggregated_timeseries_data_selector_input_object)
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
    the `timeseriesData` field.
    """
    field(:default_aggregation, :aggregation)

    @desc ~s"""
    The supported aggregations for this metric. For more information about
    aggregations see the documentation for `defaultAggregation`
    """
    field(:available_aggregations, list_of(:aggregation))

    @desc ~s"""
    The supported selector types for the metric. It is used to choose the
    target for which the metric is computed. Available selectors are:
      - slug - Identifies an asset/project
      - text - Provides random text/search term for the social metrics
      - holders_count - Provides the number of holders used in holders metrics

    Every metric has `availableSelectors` in its metadata, showing exactly
    which of the selectors can be used.
    """
    field(:available_selectors, list_of(:selector_name))

    @desc ~s"""
    The data type of the metric can be either timeseries or histogram.
      - Timeseries data is a sequence taken at successive equally spaced points
        in time (every 5 minutes, every day, every year, etc.).
      - Histogram data is an approximate representation of the distribution of
        numerical or categorical data. The metric is represented as a list of data
        points, where every point is represented represented by a tuple containing
        a range and a value.
    """
    field(:data_type, :metric_data_type)

    field(:is_accessible, :boolean)

    field(:is_restricted, :boolean)

    field(:restricted_from, :datetime)

    field(:restricted_to, :datetime)
  end

  object :metric do
    @desc ~s"""
    Return a list
    """
    field :broken_data, list_of(:broken_data) do
      arg(:slug, :string)
      arg(:selector, :metric_target_selector_input_object)
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      resolve(&MetricResolver.broken_data/3)
    end

    @desc ~s"""
    Return a list of 'datetime' and 'value' for a given metric, slug
    and time period.

    The 'includeIncompleteData' flag has a default value 'false'.

    Some metrics may have incomplete data for the last data point (usually today)
    as they are computed since the beginning of the day. An example is daily
    active addresses for today - at 12:00pm it will contain the data only
    for the last 12 hours, not for a whole day. This incomplete data can be
    confusing so it is excluded by default. If this incomplete data is needed,
    the flag includeIncompleteData should be set to 'true'.

    Incomplete data can still be useful. Here are two examples:
    Daily Active Addresses: The number is only going to increase during the day,
    so if the intention is to see when they reach over a threhsold the incomplete
    data gives more timely signal.

    NVT: Due to the way it is computed, the value is only going to decrease
    during the day, so if the intention is to see when it falls below a threhsold,
    the incomplete gives more timely signal.
    """
    field :timeseries_data, list_of(:metric_data) do
      arg(:slug, :string)
      arg(:selector, :metric_target_selector_input_object)
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")
      arg(:aggregation, :aggregation, default_value: nil)
      arg(:transform, :timeseries_metric_transform_input_object)
      arg(:include_incomplete_data, :boolean, default_value: false)
      arg(:caching_params, :caching_params_input_object)

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)

      cache_resolve(&MetricResolver.timeseries_data/3)
    end

    field :timeseries_data_per_slug, list_of(:metric_data_per_slug) do
      arg(:selector, :metric_target_selector_input_object)
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")
      arg(:aggregation, :aggregation, default_value: nil)
      arg(:transform, :timeseries_metric_transform_input_object)
      arg(:include_incomplete_data, :boolean, default_value: false)
      arg(:caching_params, :caching_params_input_object)

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)

      cache_resolve(&MetricResolver.timeseries_data_per_slug/3)
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
      arg(:selector, :metric_target_selector_input_object)
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:aggregation, :aggregation, default_value: nil)
      arg(:caching_params, :caching_params_input_object)

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)

      cache_resolve(&MetricResolver.aggregated_timeseries_data/3)
    end

    @desc ~s"""
    Returns the complexity that the metric would have given the timerange
    arguments. The complexity is computed as if both `value` and `datetime` fields
    are queried.
    """
    field :timeseries_data_complexity, :integer do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      resolve(&MetricResolver.timeseries_data_complexity/3)
    end

    @desc ~s"""
    A histogram is an approximate representation of the distribution of numerical or
    categorical data.

    The metric is represented as a list of data points, where every point is
    represented represented by a tuple containing a range an a value.

    Example (histogram data) The price_histogram (or spent_coins_cost) shows at what
    price were acquired the coins/tokens transacted on a given day D. The metric is
    represented as a list of price ranges and values with the following meaning: Out
    of all coins/tokens transacted on day D, value amount of them were acquired when
    the price was in the range range.

    On April 07, the bitcoins that circulated during that day were 124k and the
    average price for the day was $7307. Out of all of the 124k bitcoins, 13.8k of
    them were acquired when the price was in the range $8692.08 - $10845.62, so
    they were last moved when the price was higher. The same logic applies for all
    of the ranges.

    [
      ...
      {
        "range": [7307.7, 8692.08],
        "value": 2582.64
      },
      {
        "range": [8692.08, 10845.62],
        "value": 13804.97
      },
      {
        "range": [10845.62, 12999.16],
        "value": 130.33
      },
      ...
    ]
    """
    field :histogram_data, :histogram_data do
      arg(:slug, :string)
      arg(:selector, :metric_target_selector_input_object)
      # from datetime arg is not required for `all_spent_coins_cost` metric which calculates
      # the histogram for all time.
      arg(:from, :datetime)
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")
      arg(:limit, :integer, default_value: 20)

      # Complexity disabled due to not required `from` param. If at some point
      # the complexity is re-enabled, the document provider need to be updated
      # so `histogram_data` is inlcuded in the list of selections for which
      # the metric name is stored in process dictionary for complexity computation
      # complexity(&Complexity.from_to_interval/3)

      middleware(AccessControl)

      cache_resolve(&MetricResolver.histogram_data/3)
    end

    @desc ~s"""
    A table metric is a metric represented as a 2D table and not a timeseries.

    The result is represented with three elements:
    - list of column names
    - list of row names
    - list of lists that represent the values. The length of the list is the number
    of rows and the length of every of its list elements is the number of columns.

    Example: The `labelled_exchange_balance_sum` shows the exchange balance
    of all slug-exchange pairs. Every row represents data for one exchange. Every
    cell in that row contains the exchange balance of the slug at the same
    position in the columns list for that same exchange.

    GraphQL API request:
    ```graphql
    {
      getMetric(metric: "labelled_exchange_balance_sum"){
        tableData(
          from: "2020-09-28T00:00:00Z"
          to: "2020-09-29T00:00:00Z"
          selector: { slugs: ["ethereum", "uniswap"] } ){
            rows
            columns
            values
        }
      }
    }
    ```

    On September 29 2020:
    - ethereum exchange balance on catexexchange was 341
    - uniswap exchange balance on catexexchange was 0
    - ethereum exchange balance on binance was 85802226
    - uniswap exchange balance on binance was 964953679

    {
    "data": {
      "getMetric": {
        "tableData": {
          "columns": [
            "ethereum",
            "uniswap"
          ],
          "rows": [
            "catexexchange",
            "binance",
            ...
          ],
          "values": [
            [
              341.49313850999255,
              0
            ],
            [
              85802226.14164084,
              964953679.4342929
            ],
            ...
          ]
        }
      }
    }
    """
    field :table_data, :table_data do
      arg(:slug, :string)
      arg(:selector, :metric_target_selector_input_object)
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      middleware(AccessControl)

      cache_resolve(&MetricResolver.table_data/3)
    end

    field :available_since, :datetime do
      arg(:slug, :string)
      arg(:selector, :metric_target_selector_input_object)
      cache_resolve(&MetricResolver.available_since/3)
    end

    field :last_datetime_computed_at, :datetime do
      arg(:slug, :string)
      arg(:selector, :metric_target_selector_input_object)
      cache_resolve(&MetricResolver.last_datetime_computed_at/3)
    end

    field :metadata, :metric_metadata do
      cache_resolve(&MetricResolver.get_metadata/3)
    end
  end
end
