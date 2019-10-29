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
    Sanbase.SocialData.MetricAdapter
  ]

  Module.register_attribute(__MODULE__, :available_aggregations_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :free_metrics_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :restricted_metrics_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :access_map_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :metric_module_mapping_acc, accumulate: true)

  for module <- @metric_modules do
    @available_aggregations_acc module.available_aggregations()
    @free_metrics_acc module.free_metrics()
    @restricted_metrics_acc module.restricted_metrics()
    @access_map_acc module.access_map()
    @metric_module_mapping_acc Enum.map(
                                 module.available_metrics(),
                                 fn metric -> %{metric: metric, module: module} end
                               )
  end

  @available_aggregations List.flatten(@available_aggregations_acc) |> Enum.uniq()
  @free_metrics List.flatten(@free_metrics_acc) |> Enum.uniq()
  @restricted_metrics List.flatten(@restricted_metrics_acc) |> Enum.uniq()
  @metrics_module_mapping List.flatten(@metric_module_mapping_acc) |> Enum.uniq()
  @access_map Enum.reduce(@access_map_acc, %{}, fn map, acc -> Map.merge(map, acc) end)
  @aggregation_arg_supported [nil] ++ @available_aggregations

  @metrics Enum.map(@metrics_module_mapping, & &1.metric)
  @metrics_mapset MapSet.new(@metrics)

  @doc ~s"""
  Get a given metric for an identifier and time range. The metric's aggregation
  function can be changed by the last optional parameter. The available
  aggregations are #{inspect(@available_aggregations)}. If no aggregation is provided,
  a default one (based on the metric) will be used.
  """
  def get(metric, identifier, from, to, interval, aggregation \\ nil)

  def get(_, _, _, _, _, aggregation) when aggregation not in @aggregation_arg_supported do
    {:error, "The aggregation '#{inspect(aggregation)}' is not supported"}
  end

  @doc ~s"""
  Get the aggregated value for a metric, an identifier and time range.
  The metric's aggregation function can be changed by the last optional parameter.
  The available aggregations are #{inspect(@available_aggregations)}. If no aggregation is
  provided, a default one (based on the metric) will be used.
  """
  def get_aggregated(metric, identifier, from, to, aggregation \\ nil)

  @doc ~s"""
  Get the human readable name representation of a given metric
  """
  def human_readable_name(metric)

  @doc ~s"""
  Get metadata for a given metric. This includes:
  - The minimal interval for which the metric is available
    (every 5 minutes, once a day, etc.)
  - The default aggregation applied if none is provided
  - The available aggregations for the metric
  - The available slugs for the metric
  """
  def metadata(metric)

  @doc ~s"""
  Get the first datetime for which a given metric is available for a given slug
  """
  def first_datetime(metric, slug)

  @doc ~s"""
  Get all available slugs for a given metric
  """
  def available_slugs(metric)

  for %{metric: metric, module: module} <- @metrics_module_mapping do
    def get(unquote(metric), identifier, from, to, interval, aggregation) do
      unquote(module).get(
        unquote(metric),
        identifier,
        from,
        to,
        interval,
        aggregation
      )
    end

    def get_aggregated(unquote(metric), identifier, from, to, aggregation) do
      unquote(module).get_aggregated(
        unquote(metric),
        identifier,
        from,
        to,
        aggregation
      )
    end

    def human_readable_name(unquote(metric)) do
      unquote(module).human_readable_name(unquote(metric))
    end

    def metadata(unquote(metric)) do
      unquote(module).metadata(unquote(metric))
    end

    def first_datetime(unquote(metric), slug) do
      unquote(module).first_datetime(unquote(metric), slug)
    end

    def available_slugs(unquote(metric)) do
      unquote(module).available_slugs(unquote(metric))
    end
  end

  def get(metric, _, _, _, _, _), do: metric_not_available_error(metric)
  def metadata(metric), do: metric_not_available_error(metric)
  def first_datetime(metric, _), do: metric_not_available_error(metric)

  @doc ~s"""
  Get all available aggregations
  """
  def available_aggregations(), do: @available_aggregations

  @doc ~s"""
  Get all available metrics
  """
  def available_metrics(), do: @metrics

  @doc ~s"""
  Get all slugs for which at least one of the metrics is available
  """
  def available_slugs_all_metrics() do
    # Providing a 2 element tuple `{any, integer}` will use that second element
    # as TTL for the cache key
    Sanbase.Cache.get_or_store({:metric_available_slugs_all_metrics, 1800}, fn ->
      {slugs, errors} =
        Enum.reduce(@metric_modules, {[], []}, fn module, {slugs_acc, errors} ->
          case module.available_slugs() do
            {:ok, slugs} -> {[slugs | slugs_acc], errors}
            {:error, error} -> {slugs_acc, [error | errors]}
          end
        end)

      case errors do
        [] -> slugs |> Enum.uniq()
        _ -> {:error, "Cannot fetch all available slugs"}
      end
    end)
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

  # Private functions

  defp metric_not_available_error(metric) do
    close = Enum.find(@metrics_mapset, fn m -> String.jaro_distance(metric, m) > 0.9 end)
    error_msg = "The metric '#{inspect(metric)}' is not available."

    case close do
      nil -> {:error, error_msg}
      close -> {:error, error_msg <> " Did you mean '#{close}'?"}
    end
  end
end
