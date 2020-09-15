defmodule Sanbase.Metric do
  @moduledoc """
  Dispatch module used for fetching metrics.

  This module dispatches the fetching to modules implementing the
  `Sanbase.Metric.Behaviour` behaviour. Such modules are added to the
  @metric_modules list and everything else happens automatically.
  """

  @access_map Sanbase.Metric.Helper.access_map()
  @aggregations Sanbase.Metric.Helper.aggregations()
  @aggregations_per_metric Sanbase.Metric.Helper.aggregations_per_metric()
  @free_metrics Sanbase.Metric.Helper.free_metrics()
  @histogram_metric_to_module_map Sanbase.Metric.Helper.histogram_metric_to_module_map()
  @histogram_metrics Sanbase.Metric.Helper.histogram_metrics()
  @histogram_metrics_mapset Sanbase.Metric.Helper.histogram_metrics_mapset()
  @metric_module_mapping Sanbase.Metric.Helper.metric_module_mapping()
  @metric_modules Sanbase.Metric.Helper.metric_modules()
  @metric_to_module_map Sanbase.Metric.Helper.metric_to_module_map()
  @metrics Sanbase.Metric.Helper.metrics()
  @metrics_mapset Sanbase.Metric.Helper.metrics_mapset()
  @min_plan_map Sanbase.Metric.Helper.min_plan_map()
  @restricted_metrics Sanbase.Metric.Helper.restricted_metrics()
  @timeseries_metric_to_module_map Sanbase.Metric.Helper.timeseries_metric_to_module_map()
  @timeseries_metrics Sanbase.Metric.Helper.timeseries_metrics()
  @timeseries_metrics_mapset Sanbase.Metric.Helper.timeseries_metrics_mapset()
  @table_metrics Sanbase.Metric.Helper.table_metrics()
  @table_metrics_mapset Sanbase.Metric.Helper.table_metrics_mapset()
  @table_metric_to_module_map Sanbase.Metric.Helper.table_metric_to_module_map()

  def has_metric?(metric) do
    case metric in @metrics_mapset do
      true -> true
      false -> metric_not_available_error(metric)
    end
  end

  def has_incomplete_data?(metric) do
    module = Map.get(@metric_to_module_map, metric)

    module.has_incomplete_data?(metric)
  end

  @doc ~s"""
  Get a given metric for an identifier and time range. The metric's aggregation
  function can be changed by the last optional parameter. The available
  aggregations are #{inspect(@aggregations)}. If no aggregation is provided,
  a default one (based on the metric) will be used.
  """
  def timeseries_data(metric, identifier, from, to, interval, opts \\ [])

  def timeseries_data(metric, identifier, from, to, interval, opts) do
    case Map.get(@timeseries_metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric, type: :timeseries)

      module when is_atom(module) ->
        aggregation = Keyword.get(opts, :aggregation, nil)
        identifier = transform_identifier(identifier)

        fun = fn ->
          module.timeseries_data(
            metric,
            identifier,
            from,
            to,
            interval,
            opts
          )
        end

        execute_if_aggregation_valid(fun, metric, aggregation)
    end
  end

  @doc ~s"""
  Get the aggregated value for a metric, an identifier and time range.
  The metric's aggregation function can be changed by the last optional parameter.
  The available aggregations are #{inspect(@aggregations)}. If no aggregation is
  provided, a default one (based on the metric) will be used.
  """
  def aggregated_timeseries_data(metric, identifier, from, to, opts \\ [])

  def aggregated_timeseries_data(metric, identifier, from, to, opts) do
    case Map.get(@timeseries_metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric, type: :timeseries)

      module when is_atom(module) ->
        aggregation = Keyword.get(opts, :aggregation, nil)
        identifier = transform_identifier(identifier)

        fun = fn ->
          module.aggregated_timeseries_data(
            metric,
            identifier,
            from,
            to,
            opts
          )
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
  def histogram_data(metric, identifier, from, to, interval, limit \\ 100)

  def histogram_data(metric, identifier, from, to, interval, limit) do
    case Map.get(@histogram_metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric, type: :timeseries)

      module when is_atom(module) ->
        identifier = transform_identifier(identifier)

        module.histogram_data(
          metric,
          identifier,
          from,
          to,
          interval,
          limit
        )
    end
  end

  @doc ~s"""
  Get a table for a given metric
  """

  def table_data(metric, identifier, from, to)

  def table_data(metric, identifier, from, to) do
    case Map.get(@table_metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric, type: :timeseries)

      module when is_atom(module) ->
        identifier = transform_identifier(identifier)

        module.table_data(
          metric,
          identifier,
          from,
          to
        )
    end
  end

  @doc ~s"""
  Get the human readable name representation of a given metric
  """
  def human_readable_name(metric)

  for %{metric: metric, module: module} <- @metric_module_mapping do
    def human_readable_name(unquote(metric)) do
      unquote(module).human_readable_name(unquote(metric))
    end
  end

  def human_readable_name(metric), do: metric_not_available_error(metric)

  @doc ~s"""
  Get the complexity weight of a metric. This is a multiplier applied to the
  computed complexity. Clickhouse is faster compared to Elasticsearch for fetching
  timeseries data, so it has a smaller weight
  """
  def complexity_weight(metric)

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
  def metadata(metric)

  def metadata(metric) do
    case Map.get(@metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric, type: :timeseries)

      module when is_atom(module) ->
        module.metadata(metric)
    end
  end

  @doc ~s"""
  Get the first datetime for which a given metric is available for a given slug
  """
  def first_datetime(metric, slug) do
    case Map.get(@metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric, type: :timeseries)

      module when is_atom(module) ->
        module.first_datetime(metric, slug)
    end
  end

  @doc ~s"""
  Get the datetime for which the data point with latest dt for the given metric/slug
  pair is computed.
  """
  def last_datetime_computed_at(metric, slug) do
    case Map.get(@metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric, type: :timeseries)

      module when is_atom(module) ->
        module.last_datetime_computed_at(metric, slug)
    end
  end

  @doc ~s"""
  Get all available slugs for a given metric
  """
  def available_slugs(metric) do
    case Map.get(@metric_to_module_map, metric) do
      nil ->
        metric_not_available_error(metric, type: :timeseries)

      module when is_atom(module) ->
        module.available_slugs(metric)
    end
  end

  @doc ~s"""
  Get all available aggregations
  """
  def available_aggregations(), do: @aggregations

  @doc ~s"""
  Get all available metrics.

  Available options:
  - min_interval_less_or_equal - return all metrics with min interval that is
  less or equal than a given amount (expessed as a string - 5m, 1h, etc.)
  """
  def available_metrics(opts \\ [])

  def available_metrics(opts) do
    case Keyword.get(opts, :min_interval_less_or_equal) do
      nil ->
        @metrics

      interval ->
        interval_to_sec = Sanbase.DateTimeUtils.str_to_sec(interval)

        @metrics
        |> Enum.filter(fn metric ->
          {:ok, %{min_interval: min_interval}} = metadata(metric)

          case Sanbase.DateTimeUtils.str_to_sec(min_interval) do
            seconds when seconds <= interval_to_sec -> true
            _ -> false
          end
        end)
    end
  end

  @spec available_metrics_for_slug(any) ::
          {:ok, list(String.t())} | {:nocache, {:ok, list(String.t())}}
  def available_metrics_for_slug(selector) do
    parallel_opts = [ordered: false, max_concurrency: 8, timeout: 60_000]

    parallel_fun = fn module ->
      cache_key =
        {__MODULE__, :available_metrics_for_slug, module, selector} |> Sanbase.Cache.hash()

      Sanbase.Cache.get_or_store(cache_key, fn -> module.available_metrics(selector) end)
    end

    metrics_in_modules = Sanbase.Parallel.map(@metric_modules, parallel_fun, parallel_opts)

    available_metrics =
      Enum.flat_map(metrics_in_modules, fn
        {:ok, metrics} -> metrics
        _ -> []
      end)
      |> Enum.sort()

    has_errors? =
      metrics_in_modules
      |> Enum.any?(&(not match?({:ok, _}, &1)))

    case has_errors? do
      true -> {:nocache, {:ok, available_metrics}}
      false -> {:ok, available_metrics}
    end
  end

  def available_timeseries_metrics_for_slug(selector) do
    available_metrics =
      Sanbase.Cache.get_or_store(
        {__MODULE__, :available_metrics_for_slug, selector} |> Sanbase.Cache.hash(),
        fn -> available_metrics_for_slug(selector) end
      )

    case available_metrics do
      {:nocache, {:ok, metrics}} ->
        {:nocache, {:ok, metrics -- @histogram_metrics}}

      {:ok, metrics} ->
        {:ok, metrics -- @histogram_metrics}
    end
  end

  def available_histogram_metrics_for_slug(selector) do
    available_metrics =
      Sanbase.Cache.get_or_store(
        {__MODULE__, :available_metrics_for_slug, selector} |> Sanbase.Cache.hash(),
        fn -> available_metrics_for_slug(selector) end
      )

    case available_metrics do
      {:nocache, {:ok, metrics}} ->
        {:nocache, {:ok, metrics -- @timeseries_metrics}}

      {:ok, metrics} ->
        {:ok, metrics -- @timeseries_metrics}
    end
  end

  def available_timeseries_metrics(), do: @timeseries_metrics

  def available_histogram_metrics(), do: @histogram_metrics

  def available_table_metrics(), do: @table_metrics

  @doc ~s"""
  Get all slugs for which at least one of the metrics is available
  """
  def available_slugs() do
    # Providing a 2 element tuple `{any, integer}` will use that second element
    # as TTL for the cache key
    Sanbase.Cache.get_or_store({:metric_available_slugs_all_metrics, 1800}, fn ->
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
    end)
  end

  def available_slugs_per_module() do
    Sanbase.Cache.get_or_store({:available_slugs_per_module, 1800}, fn ->
      {result, errors} =
        Enum.reduce(@metric_modules, {%{}, []}, fn module, {acc, errors} ->
          case module.available_slugs() do
            {:ok, slugs} -> {Map.put(acc, module, slugs), errors}
            {:error, error} -> {acc, [error | errors]}
          end
        end)

      case errors do
        [] -> {:ok, result}
        _ -> {:error, "Cannot fetch all available slugs per module. Errors: #{inspect(errors)}"}
      end
    end)
  end

  def available_slugs_mapset() do
    case available_slugs() do
      {:ok, list} -> {:ok, MapSet.new(list)}
      {:error, error} -> {:error, error}
    end
  end

  @doc ~s"""
  Get all free metrics
  """
  def free_metrics(), do: @free_metrics

  @doc ~s"""
  Get all restricted metrics
  """
  def restricted_metrics(), do: @restricted_metrics

  @doc ~s"""
  Get a map where the key is a metric and the value is the access level
  """
  def access_map(), do: @access_map

  @doc ~s"""
  Get a map where the key is a metric and the value is the min plan it is
  accessible in.
  """
  def min_plan_map(), do: @min_plan_map

  # Private functions

  defp metric_not_available_error(metric, opts \\ [])

  defp metric_not_available_error(metric, opts) do
    type = Keyword.get(opts, :type, :all)
    %{close: close, error_msg: error_msg} = metric_not_available_error_details(metric, type)

    case close do
      nil -> {:error, error_msg}
      close -> {:error, error_msg <> " Did you mean '#{close}'?"}
    end
  end

  defp metric_not_available_error_details(metric, :all) do
    %{
      close: Enum.find(@metrics_mapset, fn m -> String.jaro_distance(metric, m) > 0.8 end),
      error_msg: "The metric '#{metric}' is not supported or is mistyped."
    }
  end

  defp metric_not_available_error_details(metric, :timeseries) do
    %{
      close:
        Enum.find(@timeseries_metrics_mapset, fn m -> String.jaro_distance(metric, m) > 0.8 end),
      error_msg: "The timeseries metric '#{metric}' is not supported or is mistyped."
    }
  end

  defp metric_not_available_error_details(metric, :histogram) do
    %{
      close:
        Enum.find(@histogram_metrics_mapset, fn m -> String.jaro_distance(metric, m) > 0.8 end),
      error_msg: "The histogram metric '#{metric}' is not supported or is mistyped."
    }
  end

  defp transform_identifier(%{market_segments: market_segments} = selector) do
    slugs =
      Sanbase.Model.Project.List.by_market_segment_all_of(market_segments) |> Enum.map(& &1.slug)

    ignored_slugs = Map.get(selector, :ignored_slugs, [])

    %{slug: slugs -- ignored_slugs}
  end

  defp transform_identifier(identifier), do: identifier

  defp execute_if_aggregation_valid(fun, metric, aggregation) do
    aggregation_valid? = aggregation in Map.get(@aggregations_per_metric, metric)

    case aggregation_valid? do
      true ->
        fun.()

      false ->
        {:error, "The aggregation #{aggregation} is not supported for the metric #{metric}"}
    end
  end
end
