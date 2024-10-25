defmodule Sanbase.Metric.HelperNew do
  @moduledoc """
  A helper module that uses the separate metric modules and  builds maps and
  mappings that combine the data from all modules into a single place.

  This module is hiding the metric modules from the user-facing `Sanbase.Metric`
  module and makes adding new modules transparent.

  The order of modules in `@metric_modules` **does** matter.
  `Module.register_attribute/3` with `accumulate: true` option puts new
  attributes on top of the accumulated list. That means when we put them in a
  map those that are first in @metric_modules might override later ones. One
  example for this is part of social metrics which are both in
  Sanbase.Clickhouse.MetricAdapter and Sanbase.SocialData.MetricAdapter and are
  invoked with different args. The ones in `Sanbase.Clickhouse.MetricAdapter`
  will override the ones in Sanbase.SocialData.MetricAdapter.
  """

  #
  # It's important that the Price module goes before the PricePair module.
  # This way the default data shown is for the metrics from the Price module
  # This way the behavior is backward compatible
  @modules [
    Sanbase.Price.MetricAdapter,
    Sanbase.PricePair.MetricAdapter,
    Sanbase.Clickhouse.Github.MetricAdapter,
    Sanbase.SocialData.MetricAdapter,
    Sanbase.Twitter.MetricAdapter,
    Sanbase.Clickhouse.TopHolders.MetricAdapter,
    Sanbase.Clickhouse.Uniswap.MetricAdapter,
    Sanbase.BlockchainAddress.MetricAdapter,
    Sanbase.Contract.MetricAdapter,
    Sanbase.Clickhouse.MetricAdapter
  ]

  defp get(key) do
    case :persistent_term.get({__MODULE__, key}, :undefined) do
      :undefined ->
        data = compute(key)
        :persistent_term.put({__MODULE__, key}, data)
        data

      data ->
        data
    end
  end

  def access_map(), do: get(:access_map)
  def aggregations(), do: get(:aggregations)
  def aggregations_per_metric(), do: get(:aggregations_per_metric)
  def fixed_labels_parameters_metrics(), do: get(:fixed_labels_parameters_metrics)
  def free_metrics(), do: get(:free_metrics)
  def histogram_metric_module_mapping(), do: get(:histogram_metric_module_mapping)
  def histogram_metric_to_module_map(), do: get(:histogram_metric_to_module_map)
  def histogram_metrics(), do: get(:histogram_metrics)
  def histogram_metrics_mapset(), do: get(:histogram_metrics_mapset)
  def implemented_optional_functions(), do: get(:implemented_optional_functions)
  def incomplete_metrics(), do: get(:incomplete_metrics)
  def metric_module_mapping(), do: get(:metric_module_mapping)
  def metric_modules(), do: get(:metric_modules)
  def metric_to_module_map(), do: get(:metric_to_module_map)
  def metrics(), do: get(:metrics)
  def metrics_mapset(), do: get(:metrics_mapset)
  def min_plan_map(), do: get(:min_plan_map)
  def required_selectors_map(), do: get(:required_selectors_map)
  def restricted_metrics(), do: get(:restricted_metrics)
  def soft_deprecated_metrics_map(), do: get(:soft_deprecated_metrics_map)
  def table_metric_module_mapping(), do: get(:table_metric_module_mapping)
  def table_metric_to_module_map(), do: get(:table_metric_to_module_map)
  def table_metrics(), do: get(:table_metrics)
  def table_metrics_mapset(), do: get(:table_metrics_mapset)
  def timeseries_metric_module_mapping(), do: get(:timeseries_metric_module_mapping)
  def timeseries_metric_to_module_map(), do: get(:timeseries_metric_to_module_map)
  def timeseries_metrics(), do: get(:timeseries_metrics)
  def timeseries_metrics_mapset(), do: get(:timeseries_metrics_mapset)

  # Private functions

  defp compute(:access_map) do
    Enum.reduce(@modules, %{}, fn module, acc ->
      module_access_map = module.access_map()
      Map.merge(acc, module_access_map)
    end)
  end

  defp compute(:aggregations) do
    Enum.reduce(@modules, [], fn module, acc ->
      aggregations = module.available_aggregations()
      aggregations ++ acc
    end)
    |> Enum.uniq()
  end

  defp compute(:aggregations_per_metric) do
    for module <- modules,
        metrics <- module.available_metrics(),
        metric <- [metrics],
        {:ok, metadata} <- module.metadata(metric),
        reduce: %{} do
      acc ->
        Map.put_new(acc, metric, [nil] ++ metadata.aggregations)
    end
  end
end
