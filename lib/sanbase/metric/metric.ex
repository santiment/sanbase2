defmodule Sanbase.Metric do
  @moduledoc """
  Dispatch module used for fetching metrics.

  This module dispatches the fetching to modules implementing the
  `Sanbase.Metric.Behaviour` behaviour. Such modules are added to the
  @metric_modules list and everything else happens automatically.
  """

  alias Sanbase.Clickhouse

  @metric_modules [
    Clickhouse.Github.MetricAdapter,
    Clickhouse.Metric,
    Sanbase.SocialData.MetricAdapter,
    Sanbase.Price.MetricAdapter,
    Sanbase.Twitter.MetricAdapter,
    Sanbase.Clickhouse.TopHolders.MetricAdapter
  ]

  Module.register_attribute(__MODULE__, :aggregations_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :aggregations_per_metric_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :free_metrics_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :restricted_metrics_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :access_map_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :min_plan_map_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :timeseries_metric_module_mapping_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :histogram_metric_module_mapping_acc, accumulate: true)

  for module <- @metric_modules do
    @aggregations_acc module.available_aggregations()
    @free_metrics_acc module.free_metrics()
    @restricted_metrics_acc module.restricted_metrics()
    @access_map_acc module.access_map()
    @min_plan_map_acc module.min_plan_map()

    @aggregations_per_metric_acc Enum.into(
                                   module.available_metrics(),
                                   %{},
                                   fn metric ->
                                     {:ok, %{available_aggregations: aggr}} =
                                       module.metadata(metric)

                                     {metric, [nil] ++ aggr}
                                   end
                                 )

    @timeseries_metric_module_mapping_acc Enum.map(
                                            module.available_timeseries_metrics(),
                                            fn metric -> %{metric: metric, module: module} end
                                          )

    @histogram_metric_module_mapping_acc Enum.map(
                                           module.available_histogram_metrics(),
                                           fn metric -> %{metric: metric, module: module} end
                                         )
  end

  @aggregations List.flatten(@aggregations_acc) |> Enum.uniq()
  @free_metrics List.flatten(@free_metrics_acc) |> Enum.uniq()
  @restricted_metrics List.flatten(@restricted_metrics_acc) |> Enum.uniq()
  @timeseries_metric_module_mapping List.flatten(@timeseries_metric_module_mapping_acc)
                                    |> Enum.uniq()

  @histogram_metric_module_mapping List.flatten(@histogram_metric_module_mapping_acc)
                                   |> Enum.uniq()

  @metric_module_mapping (@histogram_metric_module_mapping ++ @timeseries_metric_module_mapping)
                         |> Enum.uniq()

  @metric_to_module_map @metric_module_mapping
                        |> Enum.into(%{}, fn %{metric: metric, module: module} ->
                          {metric, module}
                        end)

  @aggregations_per_metric Enum.reduce(@aggregations_per_metric_acc, %{}, &Map.merge(&1, &2))
  @access_map Enum.reduce(@access_map_acc, %{}, &Map.merge(&1, &2))
  @min_plan_map Enum.reduce(@min_plan_map_acc, %{}, &Map.merge(&1, &2))

  @metrics Enum.map(@metric_module_mapping, & &1.metric)
  @timeseries_metrics Enum.map(@timeseries_metric_module_mapping, & &1.metric)
  @histogram_metrics Enum.map(@histogram_metric_module_mapping, & &1.metric)

  @metrics_mapset MapSet.new(@metrics)
  @timeseries_metrics_mapset MapSet.new(@timeseries_metrics)
  @histogram_metrics_mapset MapSet.new(@histogram_metrics)

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
  def timeseries_data(metric, identifier, from, to, interval, aggregation \\ nil)

  for %{metric: metric, module: module} <- @timeseries_metric_module_mapping do
    def timeseries_data(unquote(metric), identifier, from, to, interval, aggregation)
        when aggregation in unquote(Map.get(@aggregations_per_metric, metric)) do
      unquote(module).timeseries_data(
        unquote(metric),
        identifier,
        from,
        to,
        interval,
        aggregation
      )
    end
  end

  def timeseries_data(metric, _, _, _, _, aggregation) do
    cond do
      metric not in @metrics_mapset ->
        metric_not_available_error(metric, type: :timeseries)

      aggregation not in Map.get(@aggregations_per_metric, metric) ->
        {:error, "The aggregation #{aggregation} is not supported for the metric #{metric}"}
    end
  end

  @doc ~s"""
  Get the aggregated value for a metric, an identifier and time range.
  The metric's aggregation function can be changed by the last optional parameter.
  The available aggregations are #{inspect(@aggregations)}. If no aggregation is
  provided, a default one (based on the metric) will be used.
  """
  def aggregated_timeseries_data(metric, identifier, from, to, aggregation \\ nil)

  for %{metric: metric, module: module} <- @timeseries_metric_module_mapping do
    def aggregated_timeseries_data(unquote(metric), identifier, from, to, aggregation)
        when aggregation in unquote(Map.get(@aggregations_per_metric, metric)) do
      unquote(module).aggregated_timeseries_data(
        unquote(metric),
        identifier,
        from,
        to,
        aggregation
      )
    end
  end

  def aggregated_timeseries_data(metric, _, _, _, aggregation) do
    cond do
      metric not in @metrics_mapset ->
        metric_not_available_error(metric, type: :timeseries)

      aggregation not in Map.get(@aggregations_per_metric, metric) ->
        {:error, "The aggregation #{aggregation} is not supported for the metric #{metric}"}

      true ->
        {:error, "Error fetching metric #{metric} with aggregation #{aggregation}"}
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
  def slugs_by_filter(metric, from, to, operation, threshold, aggregation \\ nil)

  for %{metric: metric, module: module} <- @timeseries_metric_module_mapping do
    def slugs_by_filter(unquote(metric), from, to, operation, threshold, aggregation)
        when aggregation in unquote(Map.get(@aggregations_per_metric, metric)) do
      unquote(module).slugs_by_filter(
        unquote(metric),
        from,
        to,
        operation,
        threshold,
        aggregation
      )
    end
  end

  def slugs_by_filter(metric, _from, _to, _operation, _threshold, aggregation) do
    cond do
      metric not in @metrics_mapset ->
        metric_not_available_error(metric, type: :timeseries)

      aggregation not in Map.get(@aggregations_per_metric, metric) ->
        {:error, "The aggregation #{aggregation} is not supported for the metric #{metric}"}

      true ->
        {:error, "Error fetching slugs by filter for #{metric}"}
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
  def slugs_order(metric, from, to, direction, aggregation \\ nil)

  for %{metric: metric, module: module} <- @timeseries_metric_module_mapping do
    def slugs_order(unquote(metric), from, to, direction, aggregation)
        when aggregation in unquote(Map.get(@aggregations_per_metric, metric)) do
      unquote(module).slugs_order(
        unquote(metric),
        from,
        to,
        direction,
        aggregation
      )
    end
  end

  def slugs_order(metric, _from, _to, _direction, aggregation) do
    cond do
      metric not in @metrics_mapset ->
        metric_not_available_error(metric, type: :timeseries)

      aggregation not in Map.get(@aggregations_per_metric, metric) ->
        {:error, "The aggregation #{aggregation} is not supported for the metric #{metric}"}

      true ->
        {:error, "Error fetching slugs order for #{metric}"}
    end
  end

  @doc ~s"""
  Get a histogram for a given metric
  """
  def histogram_data(metric, identifier, from, to, interval, limit \\ 100)

  for %{metric: metric, module: module} <- @histogram_metric_module_mapping do
    def histogram_data(unquote(metric), identifier, from, to, interval, limit) do
      unquote(module).histogram_data(
        unquote(metric),
        identifier,
        from,
        to,
        interval,
        limit
      )
    end
  end

  def histogram_data(metric, _, _, _, _, _),
    do: metric_not_available_error(metric, type: :histogram)

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

  for %{metric: metric, module: module} <- @metric_module_mapping do
    def complexity_weight(unquote(metric)) do
      unquote(module).complexity_weight(unquote(metric))
    end
  end

  def complexity_weight(metric), do: metric_not_available_error(metric)

  @doc ~s"""
  Get metadata for a given metric. This includes:
  - The minimal interval for which the metric is available
    (every 5 minutes, once a day, etc.)
  - The default aggregation applied if none is provided
  - The available aggregations for the metric
  - The available slugs for the metric
  """
  def metadata(metric)

  for %{metric: metric, module: module} <- @metric_module_mapping do
    def metadata(unquote(metric)) do
      unquote(module).metadata(unquote(metric))
    end
  end

  def metadata(metric), do: metric_not_available_error(metric)

  @doc ~s"""
  Get the first datetime for which a given metric is available for a given slug
  """
  def first_datetime(metric, slug)

  for %{metric: metric, module: module} <- @metric_module_mapping do
    def first_datetime(unquote(metric), selector) do
      unquote(module).first_datetime(unquote(metric), selector)
    end
  end

  def first_datetime(metric, _), do: metric_not_available_error(metric)

  def last_datetime_computed_at(metric, slug)

  for %{metric: metric, module: module} <- @metric_module_mapping do
    def last_datetime_computed_at(unquote(metric), slug) do
      unquote(module).last_datetime_computed_at(unquote(metric), slug)
    end
  end

  def last_datetime_computed_at(metric, _), do: metric_not_available_error(metric)

  @doc ~s"""
  Get all available slugs for a given metric
  """
  def available_slugs(metric)

  for %{metric: metric, module: module} <- @metric_module_mapping do
    def available_slugs(unquote(metric)) do
      unquote(module).available_slugs(unquote(metric))
    end
  end

  def available_slugs(metric), do: metric_not_available_error(metric)

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
    metrics_in_modules =
      Sanbase.Parallel.map(@metric_modules, fn module -> module.available_metrics(selector) end,
        ordered: false,
        max_concurrency: 8,
        timeout: 60_000
      )

    available_metrics =
      Enum.flat_map(metrics_in_modules, fn
        {:ok, metrics} -> metrics
        _ -> []
      end)
      |> Enum.sort()

    has_errors? =
      metrics_in_modules
      |> Enum.any?(&(not match?({:ok, _}, &1)))

    available_metrics = remove_metrics_manually(selector, available_metrics)

    case has_errors? do
      true -> {:nocache, {:ok, available_metrics}}
      false -> {:ok, available_metrics}
    end
  end

  # Temporary remove bitcoin exchange metrics from the lists of available metrics
  defp remove_metrics_manually(%{slug: "bitcoin"}, metrics) do
    metrics |> Enum.reject(&String.contains?(&1, "exchange"))
  end

  defp remove_metrics_manually(_selector, metrics), do: metrics

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
end
