defmodule Sanbase.Metric do
  @moduledoc """
  Dispatch module used for fetching metrics.

  This module dispatches the fetching to modules implementing the
  `Sanbase.Metric.Behaviour` behaviour. Such modules are added to the
  @metric_modules list and everything else happens automatically.

  This project is a data-centric application and the metrics are one of the
  main data types provided.

  The module works by either dispatching the functions to the proper module or
  by aggregating data fetched by multiple modules.
  """

  import Sanbase.Metric.MetricReplace,
    only: [maybe_replace_metric: 2, maybe_replace_metrics: 2]

  import Sanbase.Utils.Transform, only: [maybe_sort: 3, maybe_apply_function: 2]

  # Use only the types from the behaviour module
  alias Sanbase.Metric.Behaviour, as: Type
  alias Sanbase.Metric.Helper
  alias Sanbase.Clickhouse.MetricAdapter.FileHandler

  @compile inline: [
             execute_if_aggregation_valid: 3,
             maybe_change_module: 4,
             combine_metrics_in_modules: 2
           ]

  @type datetime :: DateTime.t()
  @type metric :: Type.metric()
  @type selector :: Type.selector()
  @type interval :: Type.interval()
  @type operation :: Type.operation()
  @type threshold :: Type.threshold()
  @type direction :: Type.direction()
  @type opts :: Type.opts()

  @typedoc """
  This type is used when the available metrics from many modules are gathered.
  It might be the case that one of these modlues cannot fetch some data (the
  service it uses is down). In this case, instead of breaking everything and
  returning error, return a :nocache result. This will make the API not cache
  the result and the subsequent call will try to compute the result again.
  """
  @type available_metrics_with_nocache_result ::
          {:ok, list(metric)} | {:nocache, {:ok, list(metric)}}

  @access_map Helper.access_map()
  @aggregations Helper.aggregations()
  @aggregations_per_metric Helper.aggregations_per_metric()
  @incomplete_metrics Helper.incomplete_metrics()
  @free_metrics Helper.free_metrics()
  @histogram_metric_to_module_map Helper.histogram_metric_to_module_map()
  @histogram_metrics Helper.histogram_metrics()
  @histogram_metrics_mapset Helper.histogram_metrics_mapset()
  @metric_modules Helper.metric_modules()
  @metric_to_module_map Helper.metric_to_module_map()
  @metrics Helper.metrics()
  @metrics_mapset Helper.metrics_mapset()
  @min_plan_map Helper.min_plan_map()
  @restricted_metrics Helper.restricted_metrics()
  @timeseries_metric_to_module_map Helper.timeseries_metric_to_module_map()
  @timeseries_metrics Helper.timeseries_metrics()
  @timeseries_metrics_mapset Helper.timeseries_metrics_mapset()
  @table_metrics Helper.table_metrics()
  @table_metrics_mapset Helper.table_metrics_mapset()
  @table_metric_to_module_map Helper.table_metric_to_module_map()
  @required_selectors_map Helper.required_selectors_map()
  @deprecated_metrics_map Helper.deprecated_metrics_map()
  @soft_deprecated_metrics_map Helper.soft_deprecated_metrics_map()

  @doc ~s"""
  Check if `metric` is a valid metric name.
  """
  @spec has_metric?(any()) :: true | {:error, String.t()}
  def has_metric?(metric) do
    case metric in @metrics_mapset do
      true -> true
      false -> metric_not_available_error(metric)
    end
  end

  def required_selectors(metric) do
    case metric in @metrics_mapset do
      true -> {:ok, Map.get(@required_selectors_map, metric, [])}
      false -> metric_not_available_error(metric)
    end
  end

  def is_not_deprecated?(metric) do
    now = DateTime.utc_now()
    hard_deprecate_after = Map.get(@deprecated_metrics_map, metric)

    # The metric is not deprecated if `hard_deprecate_after` is nil or if the the
    # date is in the future
    case is_nil(hard_deprecate_after) or DateTime.compare(now, hard_deprecate_after) == :lt do
      true -> true
      false -> {:error, "The metric #{metric} is deprecated since #{hard_deprecate_after}"}
    end
  end

  @doc ~s"""
  Check if a metric has incomplete data.

  Incomplete data applies to daily metrics, whose value for the current day
  is updated many times throughout the day. For example, the value for Daily
  Active Addresses at 18:00 contains only for 3/4 of the day. The value for a given
  day becomes constant only when the next day starts.
  """
  @spec has_incomplete_data?(Sanbase.Metric.Behaviour.metric()) :: boolean()
  def has_incomplete_data?(metric) do
    module = Map.get(@metric_to_module_map, metric)

    module.has_incomplete_data?(metric)
  end

  def broken_data(metric, selector, from, to) do
    metric = maybe_replace_metric(metric, selector)

    case Map.get(@metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric)

      module when is_atom(module) ->
        module = maybe_change_module(module, metric, selector, [])
        module.broken_data(metric, selector, from, to)
    end
  end

  @doc ~s"""
  Returns timeseries data (pairs of datetime and float value) for a given set
  of arguments.

  Get a given metric for an interval and time range. The metric's aggregation
  function can be changed by the last optional parameter. The available
  aggregations are #{inspect(@aggregations)}. If no aggregation is provided,
  a default one (based on the metric) will be used.
  """
  @spec timeseries_data(metric, selector, datetime, datetime, interval, opts) ::
          Type.timeseries_data_result()
  def timeseries_data(metric, selector, from, to, interval, opts \\ [])

  def timeseries_data(metric, selector, from, to, interval, opts) do
    metric = maybe_replace_metric(metric, selector)

    case Map.get(@timeseries_metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric, type: :timeseries)

      module when is_atom(module) ->
        module = maybe_change_module(module, metric, selector, opts)
        aggregation = Keyword.get(opts, :aggregation, nil)

        fun = fn ->
          module.timeseries_data(
            metric,
            selector,
            from,
            to,
            interval,
            opts
          )
          |> maybe_round_floats(:timeseries_data)
        end

        execute_if_aggregation_valid(fun, metric, aggregation)
    end
  end

  @doc ~s"""
  Returns timeseries data (pairs of datetime and float value) for every slug
  separately.

  Get a given metric for an selector and time range. The metric's aggregation
  function can be changed by the last optional parameter. The available
  aggregations are #{inspect(@aggregations)}. If no aggregation is provided,
  a default one (based on the metric) will be used.
  """
  @spec timeseries_data_per_slug(metric, selector, datetime, datetime, interval, opts) ::
          Type.timeseries_data_per_slug_result()
  def timeseries_data_per_slug(metric, selector, from, to, interval, opts \\ [])

  def timeseries_data_per_slug(metric, selector, from, to, interval, opts) do
    metric = maybe_replace_metric(metric, selector)

    case Map.get(@timeseries_metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric, type: :timeseries)

      module when is_atom(module) ->
        module = maybe_change_module(module, metric, selector, opts)
        aggregation = Keyword.get(opts, :aggregation, nil)

        fun = fn ->
          module.timeseries_data_per_slug(
            metric,
            selector,
            from,
            to,
            interval,
            opts
          )
          |> maybe_round_floats(:timeseries_data_per_slug)
        end

        execute_if_aggregation_valid(fun, metric, aggregation)
        |> maybe_sort(:datetime, :asc)
        |> maybe_apply_function(&sort_data_field_by_slug_asc/1)
    end
  end

  @doc ~s"""
  Get the aggregated value for a metric, an selector and time range.
  The metric's aggregation function can be changed by the last optional parameter.
  The available aggregations are #{inspect(@aggregations)}. If no aggregation is
  provided, a default one (based on the metric) will be used.
  """
  @spec aggregated_timeseries_data(metric, selector, datetime, datetime, opts) ::
          Type.aggregated_timeseries_data_result()
  def aggregated_timeseries_data(metric, selector, from, to, opts \\ [])

  def aggregated_timeseries_data(metric, selector, from, to, opts) do
    metric = maybe_replace_metric(metric, selector)

    case Map.get(@timeseries_metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric, type: :timeseries)

      module when is_atom(module) ->
        module = maybe_change_module(module, metric, selector, opts)
        aggregation = Keyword.get(opts, :aggregation, nil)

        fun = fn ->
          module.aggregated_timeseries_data(
            metric,
            selector,
            from,
            to,
            opts
          )
          |> maybe_round_floats(:aggregated_timeseries_data)
        end

        execute_if_aggregation_valid(fun, metric, aggregation)
    end
  end

  @doc ~s"""
  Get a list of all slugs that satisfy a given filter

  The filtering is determined by the aggregated values of the value of `metric`,
  aggregated in the `from`-`to` interval, aggregated by `aggregation`. Of all
  slugs, only those whose value is satisfying the `operator` and `threshold` checks
  are taken.

  If no aggregation is provided, a default one (based on the metric) will be used.
  """
  @spec slugs_by_filter(metric, datetime, datetime, operation, threshold, opts) ::
          Type.slugs_by_filter_result()
  def slugs_by_filter(metric, from, to, operation, threshold, opts \\ [])

  def slugs_by_filter(metric, from, to, operation, threshold, opts) do
    case Map.get(@timeseries_metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric, type: :timeseries)

      module when is_atom(module) ->
        aggregation = Keyword.get(opts, :aggregation, nil)

        fun = fn ->
          module.slugs_by_filter(
            metric,
            from,
            to,
            operation,
            threshold,
            opts
          )
        end

        execute_if_aggregation_valid(fun, metric, aggregation)
    end
  end

  @doc ~s"""
  Get a list of all slugs in a specific order.

  The order is determined by the aggregated values of the value of `metric`,
  aggregated in the `from`-`to` interval, aggregated by `aggregation`.
  The order is either in ascending or descending order, defined by the `direction`
  argument with two values - :asc and :desc
  If no aggregation is provided, a default one (based on the metric) will be used.
  """
  @spec slugs_order(metric, datetime, datetime, direction, opts) ::
          Type.slugs_order_result()
  def slugs_order(metric, from, to, direction, opts \\ [])

  def slugs_order(metric, from, to, direction, opts) do
    case Map.get(@metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric, type: :timeseries)

      module when is_atom(module) ->
        aggregation = Keyword.get(opts, :aggregation, nil)

        fun = fn ->
          module.slugs_order(
            metric,
            from,
            to,
            direction,
            opts
          )
        end

        execute_if_aggregation_valid(fun, metric, aggregation)
    end
  end

  @doc ~s"""
  Get a histogram for a given metric
  """
  @spec histogram_data(metric, selector, datetime, datetime, interval, non_neg_integer()) ::
          Type.histogram_data_result()
  def histogram_data(metric, selector, from, to, interval, limit \\ 100)

  def histogram_data(metric, selector, from, to, interval, limit) do
    metric = maybe_replace_metric(metric, selector)

    case Map.get(@histogram_metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric, type: :histogram)

      module when is_atom(module) ->
        module = maybe_change_module(module, metric, selector, [])

        module.histogram_data(
          metric,
          selector,
          from,
          to,
          interval,
          limit
        )
    end
  end

  @doc ~s"""
  Get a table for a given metric.

  Take a look at the `TableMetric` modules.
  """
  @spec table_data(metric, selector, datetime, datetime, opts()) ::
          Type.table_data_result()
  def table_data(metric, selector, from, to, opts \\ [])

  def table_data(metric, selector, from, to, opts) do
    metric = maybe_replace_metric(metric, selector)

    case Map.get(@table_metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric, type: :table)

      module when is_atom(module) ->
        module = maybe_change_module(module, metric, selector, opts)
        aggregation = Keyword.get(opts, :aggregation, nil)

        fun = fn ->
          module.table_data(
            metric,
            selector,
            from,
            to,
            opts
          )
        end

        execute_if_aggregation_valid(fun, metric, aggregation)
    end
  end

  @doc ~s"""
  Get the human readable name representation of a given metric
  """
  @spec human_readable_name(metric) :: Type.human_readable_name_result()
  def human_readable_name(metric) do
    case Map.get(@metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric)

      module when is_atom(module) ->
        module.human_readable_name(metric)
    end
  end

  @doc ~s"""
  Get the complexity weight of a metric. This is a multiplier applied to the
  computed complexity. Clickhouse is faster compared to Elasticsearch for fetching
  timeseries data, so it has a smaller weight
  """
  @spec complexity_weight(metric) :: Type.complexity_weight()
  def complexity_weight(metric) do
    case Map.get(@metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric, type: :timeseries)

      module when is_atom(module) ->
        module.complexity_weight(metric)
    end
  end

  @doc ~s"""
  Get metadata for a given metric. This includes:
  - The minimal interval for which the metric is available
    (every 5 minutes, once a day, etc.)
  - The default aggregation applied if none is provided
  - The available aggregations for the metric
  - The available slugs for the metric
  """
  @spec metadata(metric) :: Type.metadata_result()
  def metadata(metric) do
    case Map.get(@metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric, type: :timeseries)

      module when is_atom(module) ->
        case module.metadata(metric) do
          {:ok, metadata} -> {:ok, extend_metadata(metadata, metric)}
          error -> error
        end
    end
  end

  @doc ~s"""
  Get the first datetime for which a given metric is available for a given slug
  """
  @spec first_datetime(metric, selector, opts) :: Type.first_datetime_result()
  def first_datetime(metric, selector, opts) do
    metric = maybe_replace_metric(metric, selector)

    case Map.get(@metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric, type: :timeseries)

      module when is_atom(module) ->
        module = maybe_change_module(module, metric, selector, opts)
        module.first_datetime(metric, selector)
    end
  end

  @doc ~s"""
  Get the datetime for which the data point with latest dt for the given metric/slug
  pair is computed.
  """
  @spec last_datetime_computed_at(metric, selector, opts) ::
          Type.last_datetime_computed_at_result()
  def last_datetime_computed_at(metric, selector, opts) do
    metric = maybe_replace_metric(metric, selector)

    case Map.get(@metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric, type: :timeseries)

      module when is_atom(module) ->
        module = maybe_change_module(module, metric, selector, opts)
        module.last_datetime_computed_at(metric, selector)
    end
  end

  @doc ~s"""
  Get all available slugs for a given metric
  """
  @spec available_slugs(metric, opts) :: Type.available_slugs_result()
  def available_slugs(metric, opts \\ [])

  def available_slugs(metric, opts) do
    case Map.get(@metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric, type: :timeseries)

      module when is_atom(module) ->
        module = maybe_change_module(module, metric, %{}, opts)

        case module.available_slugs(metric) do
          {:ok, slugs} ->
            supported_slugs = Sanbase.Project.List.projects_slugs()

            slugs =
              MapSet.intersection(MapSet.new(slugs), MapSet.new(supported_slugs))
              |> Enum.to_list()

            {:ok, slugs}

          error ->
            error
        end
    end
  end

  @doc ~s"""
  Get all available aggregations
  """
  @spec available_aggregations :: list(Type.aggregation())
  def available_aggregations(), do: @aggregations

  @doc ~s"""
  Get all available metrics.

  Available options:
  - min_interval_less_or_equal - return all metrics with min interval that is
  less or equal than a given amount (expessed as a string - 5m, 1h, etc.)
  """
  @spec available_metrics(opts) :: list(metric)
  def available_metrics(opts \\ [])

  def available_metrics([]), do: @metrics

  def available_metrics(opts) do
    case Keyword.get(opts, :filter) do
      nil ->
        @metrics

      :min_interval_less_or_equal ->
        filter_interval = Keyword.fetch!(opts, :filter_interval)
        filter_metrics_by_min_interval(@metrics, filter_interval, &<=/2)

      :min_interval_greater_or_equal ->
        filter_interval = Keyword.fetch!(opts, :filter_interval)
        filter_metrics_by_min_interval(@metrics, filter_interval, &>=/2)
    end
  end

  @doc ~s"""
  Get the available metrics for a given slug.
  The available metrics list is the combination of the available metrics lists
  of every metric module.
  """
  @spec available_metrics_for_selector(any) :: available_metrics_with_nocache_result

  def available_metrics_for_selector(%{address: _address}) do
    metrics =
      FileHandler.selectors_map()
      |> Enum.filter(fn {_k, v} -> :address in v end)
      |> Enum.map(fn {k, _v} -> k end)

    {:ok, metrics}
  end

  def available_metrics_for_selector(selector) do
    parallel_opts = [ordered: false, max_concurrency: 8, timeout: 60_000]

    parallel_fun = fn module ->
      cache_key =
        {__MODULE__, :available_metrics_for_selector_in_module, module, selector}
        |> Sanbase.Cache.hash()

      Sanbase.Cache.get_or_store(cache_key, fn -> module.available_metrics(selector) end)
    end

    metrics_in_modules = Sanbase.Parallel.map(@metric_modules, parallel_fun, parallel_opts)

    combine_metrics_in_modules(metrics_in_modules, selector)
  end

  @doc ~s"""
  Get the available timeseries metrics for a given slug.
  The result is a subset of available_metrics_for_slug/1
  """
  @spec available_timeseries_metrics_for_slug(any) :: available_metrics_with_nocache_result
  def available_timeseries_metrics_for_slug(selector) do
    available_metrics =
      Sanbase.Cache.get_or_store(
        {__MODULE__, :available_metrics_for_slug, selector} |> Sanbase.Cache.hash(),
        fn -> available_metrics_for_selector(selector) end
      )

    case available_metrics do
      {:nocache, {:ok, metrics}} ->
        {:nocache, {:ok, metrics -- (@histogram_metrics ++ @table_metrics)}}

      {:ok, metrics} ->
        {:ok, metrics -- (@histogram_metrics ++ @table_metrics)}
    end
  end

  @doc ~s"""
  Get the available histogram metrics for a given slug.
  The result is a subset of available_metrics_for_slug/1
  """
  @spec available_histogram_metrics_for_slug(any) :: available_metrics_with_nocache_result
  def available_histogram_metrics_for_slug(selector) do
    available_metrics =
      Sanbase.Cache.get_or_store(
        {__MODULE__, :available_metrics_for_slug, selector} |> Sanbase.Cache.hash(),
        fn -> available_metrics_for_selector(selector) end
      )

    case available_metrics do
      {:nocache, {:ok, metrics}} ->
        {:nocache, {:ok, metrics -- (@timeseries_metrics ++ @table_metrics)}}

      {:ok, metrics} ->
        {:ok, metrics -- (@timeseries_metrics ++ @table_metrics)}
    end
  end

  @doc ~s"""
  Get the available table metrics for a given slug.
  The result is a subset of available_metrics_for_slug/1
  """
  @spec available_table_metrics_for_slug(any) :: available_metrics_with_nocache_result
  def available_table_metrics_for_slug(selector) do
    available_metrics =
      Sanbase.Cache.get_or_store(
        {__MODULE__, :available_metrics_for_slug, selector} |> Sanbase.Cache.hash(),
        fn -> available_metrics_for_selector(selector) end
      )

    case available_metrics do
      {:nocache, {:ok, metrics}} ->
        {:nocache, {:ok, metrics -- (@timeseries_metrics ++ @histogram_metrics)}}

      {:ok, metrics} ->
        {:ok, metrics -- (@timeseries_metrics ++ @histogram_metrics)}
    end
  end

  @doc ~s"""
  Get all available timeseries metrics
  """
  @spec available_timeseries_metrics() :: list(metric)
  def available_timeseries_metrics(), do: @timeseries_metrics

  @doc ~s"""
  Get all available histogram metrics
  """
  @spec available_histogram_metrics() :: list(metric)
  def available_histogram_metrics(), do: @histogram_metrics

  @doc ~s"""
  Get all available table metrics
  """
  @spec available_table_metrics() :: list(metric)
  def available_table_metrics(), do: @table_metrics

  @doc ~s"""
  Get all slugs for which at least one of the metrics is available
  """
  @spec available_slugs() :: Type.available_slugs_result()
  def available_slugs() do
    # Providing a 2 element tuple `{any, integer}` will use that second element
    # as TTL for the cache key
    cache_key = {__MODULE__, :available_slugs_all_metrics} |> Sanbase.Cache.hash()

    Sanbase.Cache.get_or_store({cache_key, 1800}, &get_available_slugs/0)
  end

  @doc ~s"""
  Get all incomplete metrics
  """
  @spec incomplete_metrics() :: list(metric)
  def incomplete_metrics(), do: @incomplete_metrics

  @doc ~s"""
  Get all free metrics
  """
  @spec free_metrics() :: list(metric)
  def free_metrics(), do: @free_metrics

  @doc ~s"""
  Get all restricted metrics
  """
  @spec restricted_metrics() :: list(metric)
  def restricted_metrics(), do: @restricted_metrics

  @doc ~s"""
  Get a map where the key is a metric and the value is the access level
  """
  @spec access_map() :: map()
  def access_map(), do: @access_map

  @doc ~s"""
  Checks if historical data is allowed for a given `metric`
  """
  @spec is_historical_data_freely_available?(metric) :: boolean
  def is_historical_data_freely_available?(metric) do
    get_in(@access_map, [metric, "historical"]) == :free
  end

  @doc ~s"""
  Checks if realtime data is allowed for a given `metric`
  """
  @spec is_realtime_data_freely_available?(metric) :: boolean
  def is_realtime_data_freely_available?(metric) do
    get_in(@access_map, [metric, "realtime"]) == :free
  end

  @doc ~s"""
  Get a map where the key is a metric and the value is the min plan it is
  accessible in.
  """
  @spec min_plan_map() :: map()
  def min_plan_map(), do: @min_plan_map

  # Private functions

  defp metric_not_available_error(metric, opts \\ [])

  defp metric_not_available_error(metric, opts) do
    type = Keyword.get(opts, :type, :all)
    %{close: close, error_msg: error_msg} = metric_not_available_error_details(metric, type)

    case close do
      nil -> {:error, error_msg}
      {"", close} -> {:error, error_msg <> " Did you mean the metric '#{close}'?"}
      {type, close} -> {:error, error_msg <> " Did you mean the #{type} metric '#{close}'?"}
    end
  end

  defp metric_not_available_error_details(metric, type) do
    %{
      close: maybe_get_close_metric(metric, type),
      error_msg: "The metric '#{metric}' is not supported, is deprecated or is mistyped."
    }
  end

  # Find the metric from the mapset which is clostest to the original metric.
  # The found metric must have a jaro distance bigger than 0.8
  defp find_closest(mapset, metric) do
    Enum.reduce(mapset, {nil, -1}, fn m, {max_m, max_dist} ->
      dist = String.jaro_distance(metric, m)

      case dist > max_dist do
        true -> {m, dist}
        false -> {max_m, max_dist}
      end
    end)
    |> case do
      {metric, dist} when dist > 0.8 -> metric
      _ -> nil
    end
  end

  # Returns {closest_metric_type, closest_metric}
  # The metrics of the same type are with highest priority.
  # If a metric of type timeseries is mistyped, then if there is a metric of
  # the same type with a jaro distance > 0.8 it is returned.
  defp maybe_get_close_metric(metric, type) do
    timeseries = find_closest(@timeseries_metrics_mapset, metric)
    histogram = find_closest(@histogram_metrics_mapset, metric)
    table = find_closest(@table_metrics_mapset, metric)

    case timeseries || histogram || table do
      nil ->
        nil

      _ ->
        case type do
          :all ->
            {"", timeseries || histogram || table}

          :timeseries ->
            (timeseries && {:timeseries, timeseries}) || (histogram && {:histogram, histogram}) ||
              (table && {:table, table})

          :histogram ->
            (histogram && {:histogram, histogram}) || (timeseries && {:timeseries, timeseries}) ||
              (table && {:table, table})

          :table ->
            (table && {:table, table}) || (timeseries && {:timeseries, timeseries}) ||
              (histogram && {:histogram, histogram})
        end
    end
  end

  defp execute_if_aggregation_valid(fun, metric, aggregation) do
    aggregation_valid? = aggregation in Map.get(@aggregations_per_metric, metric)

    case aggregation_valid? do
      true ->
        fun.()

      false ->
        {:error, "The aggregation #{aggregation} is not supported for the metric #{metric}"}
    end
  end

  @social_metrics Sanbase.SocialData.MetricAdapter.available_metrics()
  # When using slug, the social metrics are fetched from clickhouse
  # But when text selector is used, the metric should be fetched from Elasticsearch
  # as it cannot be precomputed due to the vast number of possible text arguments
  defp maybe_change_module(module, metric, %{text: _}, _opts) do
    case metric in @social_metrics do
      true -> Sanbase.SocialData.MetricAdapter
      false -> module
    end
  end

  defp maybe_change_module(module, metric, %{contract_address: _}, _opts) do
    case metric in @social_metrics do
      true -> Sanbase.SocialData.MetricAdapter
      false -> module
    end
  end

  @price_pair_metrics Sanbase.PricePair.MetricAdapter.available_metrics()
  defp maybe_change_module(module, metric, selector, opts)
       when metric in @price_pair_metrics do
    case Keyword.get(opts, :source) || Map.get(selector, :source) do
      "cryptocompare" ->
        Sanbase.PricePair.MetricAdapter

      # NOTE: Temporary. This will be reworked and handled in a generic way
      source when metric == "price_eth" and source != "cryptocompare" ->
        Sanbase.Clickhouse.MetricAdapter

      _ ->
        module
    end
  end

  defp maybe_change_module(module, _metric, _selector, _opts), do: module

  defp filter_metrics_by_min_interval(metrics, interval, compare_fun) do
    interval_to_sec = Sanbase.DateTimeUtils.str_to_sec(interval)

    metrics
    |> Enum.filter(fn metric ->
      {:ok, %{min_interval: min_interval}} = metadata(metric)

      min_interval_sec = Sanbase.DateTimeUtils.str_to_sec(min_interval)

      compare_fun.(min_interval_sec, interval_to_sec)
    end)
  end

  defp get_available_slugs() do
    {slugs, errors} =
      Enum.reduce(@metric_modules, {[], []}, fn module, {slugs_acc, errors} ->
        case module.available_slugs() do
          {:ok, slugs} -> {slugs ++ slugs_acc, errors}
          {:error, error} -> {slugs_acc, [error | errors]}
        end
      end)

    case errors do
      [] -> {:ok, slugs |> Enum.uniq()}
      _ -> {:error, "Cannot fetch all available slugs. Errors: #{inspect(errors)}"}
    end
  end

  defp combine_metrics_in_modules(metrics_in_modules, selector) do
    # Combine the results of the different metric modules. In case any of the
    # metric modules returned an :error tuple, wrap the result in a :nocache
    # tuple so the next attempt to fetch the data will try to fetch the metrics
    # again.
    available_metrics =
      Enum.flat_map(metrics_in_modules, fn
        {:ok, metrics} -> metrics
        _ -> []
      end)
      |> maybe_replace_metrics(selector)
      |> Enum.uniq()
      |> Enum.sort()

    has_errors? =
      metrics_in_modules
      |> Enum.any?(&(not match?({:ok, _}, &1)))

    case has_errors? do
      true -> {:nocache, {:ok, available_metrics}}
      false -> {:ok, available_metrics}
    end
  end

  defp sort_data_field_by_slug_asc(list) do
    Enum.map(list, fn %{data: data} = elem ->
      data_sorted_by_slug = Enum.sort_by(data, & &1.slug, :asc)
      %{elem | data: data_sorted_by_slug}
    end)
  end

  defp extend_metadata(metadata, metric) do
    hard_deprecate_after = Map.get(@deprecated_metrics_map, metric)
    is_soft_deprecated = Map.get(@soft_deprecated_metrics_map, metric)

    is_deprecated = not is_nil(hard_deprecate_after) or not is_nil(is_soft_deprecated)

    metadata
    |> Map.put(:is_deprecated, is_deprecated)
    |> Map.put(:hard_deprecate_after, hard_deprecate_after)
  end

  defp maybe_round_floats({:error, error}, _), do: {:error, error}

  defp maybe_round_floats({:ok, result}, :timeseries_data) do
    result = Enum.map(result, fn m -> round_map_value(m) end)
    {:ok, result}
  end

  defp maybe_round_floats({:ok, result}, :aggregated_timeseries_data) do
    result = Map.new(result, fn {k, v} -> {k, round_value(v)} end)
    {:ok, result}
  end

  defp maybe_round_floats({:ok, result}, :timeseries_data_per_slug) do
    result =
      Enum.map(result, fn %{data: data} = map ->
        # Each element is %{datetime: dt, [%{slug: slug, value: value}]}
        data = Enum.map(data, fn m -> round_map_value(m) end)

        %{map | data: data}
      end)

    {:ok, result}
  end

  defp round_map_value(map) do
    if Map.has_key?(map, :value_ohlc) do
      Map.update!(map, :value_ohlc, &round_ohlc_values(&1))
    else
      Map.update!(map, :value, &round_value/1)
    end
  end

  defp round_ohlc_values(ohlc) do
    Enum.reduce(ohlc, %{}, fn {key, value}, acc ->
      Map.put(acc, key, round_value(value))
    end)
  end

  defp round_value(num) when is_float(num), do: Float.round(num, 12)
  defp round_value(num), do: num
end
