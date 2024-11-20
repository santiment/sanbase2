defmodule Sanbase.Metric.Helper do
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

  require Logger

  # It's important that the Price module goes before the PricePair module.
  # This way the default data shown is for the metrics from the Price module
  # This way the behavior is backward compatible
  @modules [
    Sanbase.PricePair.MetricAdapter,
    Sanbase.Price.MetricAdapter,
    Sanbase.Clickhouse.Github.MetricAdapter,
    Sanbase.SocialData.MetricAdapter,
    Sanbase.Twitter.MetricAdapter,
    Sanbase.Clickhouse.TopHolders.MetricAdapter,
    Sanbase.Clickhouse.Uniswap.MetricAdapter,
    Sanbase.BlockchainAddress.MetricAdapter,
    Sanbase.Contract.MetricAdapter,
    Sanbase.Clickhouse.MetricAdapter
  ]

  def access_map(), do: get(:access_map)
  def aggregations(), do: get(:aggregations)
  def aggregations_per_metric(), do: get(:aggregations_per_metric)
  def fixed_labels_parameters_metrics(), do: get(:fixed_labels_parameters_metrics)
  def free_metrics(), do: get(:free_metrics)
  def histogram_metric_to_module_map(), do: get(:histogram_metric_to_module_map)
  def histogram_metrics(), do: get(:histogram_metrics)
  def histogram_metrics_mapset(), do: get(:histogram_metrics_mapset)
  def implemented_optional_functions(), do: get(:implemented_optional_functions)
  def incomplete_metrics(), do: get(:incomplete_metrics)
  def metric_modules(), do: @modules
  def metric_to_module_map(), do: get(:metric_to_module_map)
  def metric_to_modules_map(), do: get(:metric_to_modules_map)
  def metrics(), do: get(:metrics)
  def metrics_mapset(), do: get(:metrics_mapset)
  def min_plan_map(), do: get(:min_plan_map)
  def required_selectors_map(), do: get(:required_selectors_map)
  def restricted_metrics(), do: get(:restricted_metrics)
  def deprecated_metrics_map(), do: get(:deprecated_metrics_map)
  def soft_deprecated_metrics_map(), do: get(:soft_deprecated_metrics_map)
  def table_metric_to_module_map(), do: get(:table_metric_to_module_map)
  def table_metrics(), do: get(:table_metrics)
  def table_metrics_mapset(), do: get(:table_metrics_mapset)
  def timeseries_metric_to_module_map(), do: get(:timeseries_metric_to_module_map)
  def timeseries_metrics(), do: get(:timeseries_metrics)
  def timeseries_metrics_mapset(), do: get(:timeseries_metrics_mapset)

  @functions [
    {:access_map, []},
    {:aggregations, []},
    {:aggregations_per_metric, []},
    {:fixed_labels_parameters_metrics, []},
    {:free_metrics, []},
    {:histogram_metric_to_module_map, []},
    {:histogram_metrics, []},
    {:histogram_metrics_mapset, []},
    {:implemented_optional_functions, []},
    {:incomplete_metrics, []},
    {:metric_to_module_map, []},
    {:metric_to_modules_map, []},
    {:metrics, []},
    {:metrics_mapset, []},
    {:min_plan_map, []},
    {:required_selectors_map, []},
    {:restricted_metrics, []},
    {:deprecated_metrics_map, []},
    {:soft_deprecated_metrics_map, []},
    {:table_metric_to_module_map, []},
    {:table_metrics, []},
    {:table_metrics_mapset, []},
    {:timeseries_metric_to_module_map, []},
    {:timeseries_metrics, []},
    {:timeseries_metrics_mapset, []}
    # Not stored in persistent term
    # {:metric_modules, []},
  ]

  def refresh_stored_terms() do
    Logger.info("Refreshing stored terms in the #{__MODULE__}")

    result =
      for {fun, args} <- @functions do
        data = compute(fun, args)

        if :not_implemented == data,
          do: raise("Function #{fun} is not implemented in module #{__MODULE__}")

        result = :persistent_term.put(key(fun, args), data)
        {{fun, args}, result}
      end

    Enum.all?(result, &match?({_, :ok}, &1))
  end

  # Private functions
  defp key(fun, args), do: {__MODULE__, fun, args} |> Sanbase.Cache.hash()

  defp get(fun, args \\ []) do
    key = key(fun, args)

    case :persistent_term.get(key, :undefined) do
      :undefined ->
        data = compute(fun, args)
        :persistent_term.put(key, data)
        data

      data ->
        data
    end
  end

  defp compute(:access_map, []) do
    Enum.reduce(@modules, %{}, fn module, acc ->
      metric_to_access_map =
        module.access_map()
        |> Map.new(fn {metric, restrictions} ->
          access_map =
            case restrictions do
              restrictions when is_map(restrictions) ->
                restrictions

              restriction when restriction in [:free, :restricted] ->
                %{"historical" => restriction, "realtime" => restriction}
            end

          {metric, access_map}
        end)

      Map.merge(acc, metric_to_access_map)
    end)
  end

  defp compute(:aggregations, []) do
    Enum.reduce(@modules, [], fn module, acc ->
      aggregations = module.available_aggregations()
      aggregations ++ acc
    end)
    |> Enum.uniq()
  end

  defp compute(:aggregations_per_metric, []) do
    for module <- @modules,
        metric <- module.available_metrics(),
        reduce: %{} do
      acc ->
        # If there is a metric that has a different set of aggregations compared to
        # the other metrics in the module, this needs to be reworked to call
        # module.metadata(metric)
        Map.put(acc, metric, [nil] ++ module.available_aggregations())
    end
  end

  defp compute(:implemented_optional_functions, []) do
    Enum.reduce(@modules, %{}, fn module, acc ->
      acc
      |> put_if_implemented(module, :available_label_fqns, 1)
      |> put_if_implemented(module, :available_label_fqns, 2)
      |> put_if_implemented(module, :deprecated_metrics_map, 0)
      |> put_if_implemented(module, :soft_deprecated_metrics_map, 0)
      |> put_if_implemented(module, :fixed_labels_parameters_metrics, 0)
    end)
  end

  defp compute(:fixed_labels_parameters_metrics, []) do
    Enum.reduce(@modules, MapSet.new(), fn module, acc ->
      if function_exported?(module, :fixed_labels_parameters_metrics, 0) do
        fixed_labels_parameters_metrics = module.fixed_labels_parameters_metrics()
        MapSet.put(acc, fixed_labels_parameters_metrics)
      else
        acc
      end
    end)
  end

  defp compute(:free_metrics, []) do
    Enum.map(@modules, & &1.free_metrics())
    |> List.flatten()
    |> Enum.uniq()
  end

  defp compute(:restricted_metrics, []) do
    Enum.map(@modules, & &1.restricted_metrics())
    |> List.flatten()
    |> Enum.uniq()
  end

  defp compute(:metric_to_module_map, []) do
    for module <- @modules,
        metric <- module.available_metrics(),
        reduce: %{} do
      acc ->
        Map.put(acc, metric, module)
    end
  end

  defp compute(:metric_to_modules_map, []) do
    for module <- @modules,
        metric <- module.available_metrics(),
        reduce: %{} do
      acc ->
        Map.update(acc, metric, [module], &[module | &1])
    end
  end

  defp compute(:metrics, []) do
    Enum.map(@modules, & &1.available_metrics())
    |> List.flatten()
    |> Enum.uniq()
  end

  defp compute(:metrics_mapset, []) do
    compute(:metrics, []) |> MapSet.new()
  end

  defp compute(:timeseries_metric_to_module_map, []) do
    for module <- @modules,
        metric <- module.available_timeseries_metrics(),
        reduce: %{} do
      acc ->
        Map.put(acc, metric, module)
    end
  end

  defp compute(:timeseries_metrics, []) do
    Enum.map(@modules, & &1.available_timeseries_metrics())
    |> List.flatten()
    |> Enum.uniq()
  end

  defp compute(:timeseries_metrics_mapset, []) do
    compute(:timeseries_metrics, []) |> MapSet.new()
  end

  defp compute(:histogram_metric_to_module_map, []) do
    for module <- @modules,
        metric <- module.available_histogram_metrics(),
        reduce: %{} do
      acc ->
        Map.put(acc, metric, module)
    end
  end

  defp compute(:histogram_metrics, []) do
    Enum.map(@modules, & &1.available_histogram_metrics())
    |> List.flatten()
    |> Enum.uniq()
  end

  defp compute(:histogram_metrics_mapset, []) do
    compute(:histogram_metrics, []) |> MapSet.new()
  end

  defp compute(:table_metric_to_module_map, []) do
    for module <- @modules,
        metric <- module.available_table_metrics(),
        reduce: %{} do
      acc ->
        Map.put(acc, metric, module)
    end
  end

  defp compute(:table_metrics, []) do
    Enum.map(@modules, & &1.available_table_metrics())
    |> List.flatten()
    |> Enum.uniq()
  end

  defp compute(:table_metrics_mapset, []) do
    compute(:table_metrics, []) |> MapSet.new()
  end

  defp compute(:incomplete_metrics, []) do
    Enum.map(@modules, & &1.incomplete_metrics())
    |> List.flatten()
    |> Enum.uniq()
  end

  defp compute(:min_plan_map, []) do
    Enum.reduce(@modules, %{}, fn module, acc ->
      Map.merge(acc, module.min_plan_map())
    end)
  end

  defp compute(:deprecated_metrics_map, []) do
    Enum.reduce(@modules, %{}, fn module, acc ->
      if function_exported?(module, :deprecated_metrics_map, 0) do
        Map.merge(acc, module.deprecated_metrics_map())
      else
        acc
      end
    end)
  end

  defp compute(:soft_deprecated_metrics_map, []) do
    Enum.reduce(@modules, %{}, fn module, acc ->
      if function_exported?(module, :soft_deprecated_metrics_map, 0) do
        Map.merge(acc, module.soft_deprecated_metrics_map())
      else
        acc
      end
    end)
  end

  defp compute(:required_selectors_map, []) do
    Enum.reduce(@modules, %{}, fn module, acc ->
      Map.merge(acc, module.required_selectors())
    end)
  end

  defp compute(_function, _arguments), do: :not_implemented

  # Helper for :implemented_optional_functions
  defp put_if_implemented(acc, module, fun, arity) when is_integer(arity) do
    bool = function_exported?(module, fun, arity)
    Map.put(acc, {module, fun, arity}, bool)
  end

  @functions [
    :access_map,
    :aggregations,
    :aggregations_per_metric,
    :fixed_labels_parameters_metrics,
    :free_metrics,
    :histogram_metric_to_module_map,
    :histogram_metrics,
    :histogram_metrics_mapset,
    :implemented_optional_functions,
    :incomplete_metrics,
    :metric_to_module_map,
    :metrics,
    :metrics_mapset,
    :min_plan_map,
    :required_selectors_map,
    :restricted_metrics,
    :soft_deprecated_metrics_map,
    :table_metric_to_module_map,
    :table_metrics,
    :table_metrics_mapset,
    :timeseries_metric_to_module_map,
    :timeseries_metrics
  ]

  def not_implemented() do
    Enum.filter(@functions, fn {fun, args} -> compute(fun, args) == :not_implemented end)
  end

  def implemented() do
    Enum.filter(@functions, fn {fun, args} -> compute(fun, args) != :not_implemented end)
  end
end
