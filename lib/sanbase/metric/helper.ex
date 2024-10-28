# defmodule Sanbase.Metric.Helper do
#   @moduledoc """
#   A helper module that uses the separate metric modules and  builds maps and
#   mappings that combine the data from all modules into a single place.

#   This module is hiding the metric modules from the user-facing `Sanbase.Metric`
#   module and makes adding new modules transparent.

#   The order of modules in `@metric_modules` **does** matter.
#   `Module.register_attribute/3` with `accumulate: true` option puts new
#   attributes on top of the accumulated list. That means when we put them in a
#   map those that are first in @metric_modules might override later ones. One
#   example for this is part of social metrics which are both in
#   Sanbase.Clickhouse.MetricAdapter and Sanbase.SocialData.MetricAdapter and are
#   invoked with different args. The ones in `Sanbase.Clickhouse.MetricAdapter`
#   will override the ones in Sanbase.SocialData.MetricAdapter.
#   """

#   #
#   # It's important that the Price module goes before the PricePair module.
#   # This way the default data shown is for the metrics from the Price module
#   # This way the behavior is backward compatible
#   @compile_time_ready_metric_modules [
#     Sanbase.Clickhouse.MetricAdapter,
#     Sanbase.Price.MetricAdapter,
#     Sanbase.PricePair.MetricAdapter,
#     Sanbase.Clickhouse.Github.MetricAdapter,
#     Sanbase.SocialData.MetricAdapter,
#     Sanbase.Twitter.MetricAdapter,
#     Sanbase.Clickhouse.TopHolders.MetricAdapter,
#     Sanbase.Clickhouse.Uniswap.MetricAdapter,
#     Sanbase.BlockchainAddress.MetricAdapter,
#     Sanbase.Contract.MetricAdapter
#   ]

#   Module.register_attribute(__MODULE__, :implemented_optional_functions_acc, accumulate: true)
#   Module.register_attribute(__MODULE__, :aggregations_acc, accumulate: true)
#   Module.register_attribute(__MODULE__, :aggregations_per_metric_acc, accumulate: true)
#   Module.register_attribute(__MODULE__, :incomplete_metrics_acc, accumulate: true)
#   Module.register_attribute(__MODULE__, :free_metrics_acc, accumulate: true)
#   Module.register_attribute(__MODULE__, :restricted_metrics_acc, accumulate: true)
#   Module.register_attribute(__MODULE__, :access_map_acc, accumulate: true)
#   Module.register_attribute(__MODULE__, :min_plan_map_acc, accumulate: true)
#   Module.register_attribute(__MODULE__, :timeseries_metric_module_mapping_acc, accumulate: true)
#   Module.register_attribute(__MODULE__, :histogram_metric_module_mapping_acc, accumulate: true)
#   Module.register_attribute(__MODULE__, :table_metric_module_mapping_acc, accumulate: true)
#   Module.register_attribute(__MODULE__, :required_selectors_map_acc, accumulate: true)
#   Module.register_attribute(__MODULE__, :deprecated_metrics_acc, accumulate: true)
#   Module.register_attribute(__MODULE__, :soft_deprecated_metrics_acc, accumulate: true)
#   Module.register_attribute(__MODULE__, :fixed_labels_parameters_metrics_acc, accumulate: true)

#   for module <- @compile_time_ready_metric_modules do
#     @required_selectors_map_acc module.required_selectors()
#     @aggregations_acc module.available_aggregations()
#     @incomplete_metrics_acc module.incomplete_metrics()
#     @free_metrics_acc module.free_metrics()
#     @restricted_metrics_acc module.restricted_metrics()
#     @access_map_acc module.access_map()
#     @min_plan_map_acc module.min_plan_map()

#     aggregations_fn = fn metric ->
#       {:ok, %{available_aggregations: aggr}} = module.metadata(metric)
#       {metric, [nil] ++ aggr}
#     end

#     @aggregations_per_metric_acc Enum.into(module.available_metrics(), %{}, aggregations_fn)

#     @timeseries_metric_module_mapping_acc Enum.map(
#                                             module.available_timeseries_metrics(),
#                                             fn metric -> %{metric: metric, module: module} end
#                                           )

#     @histogram_metric_module_mapping_acc Enum.map(
#                                            module.available_histogram_metrics(),
#                                            fn metric -> %{metric: metric, module: module} end
#                                          )

#     @table_metric_module_mapping_acc Enum.map(
#                                        module.available_table_metrics(),
#                                        fn metric -> %{metric: metric, module: module} end
#                                      )

#     if function_exported?(module, :available_label_fqns, 1) and
#          function_exported?(module, :available_label_fqns, 2) do
#       @implemented_optional_functions_acc {:available_label_fqns, module, true}
#     else
#       @implemented_optional_functions_acc {:available_label_fqns, module, false}
#     end

#     if function_exported?(module, :deprecated_metrics_map, 0) do
#       @deprecated_metrics_acc module.deprecated_metrics_map()
#       @implemented_optional_functions_acc {:deprecated_metrics_map, module, true}
#     else
#       @implemented_optional_functions_acc {:deprecated_metrics_map, module, false}
#     end

#     if function_exported?(module, :soft_deprecated_metrics_map, 0) do
#       @soft_deprecated_metrics_acc module.soft_deprecated_metrics_map()
#       @implemented_optional_functions_acc {:soft_deprecated_metrics_map, module, true}
#     else
#       @implemented_optional_functions_acc {:soft_deprecated_metrics_map, module, false}
#     end

#     if function_exported?(module, :fixed_labels_parameters_metrics, 0) do
#       @fixed_labels_parameters_metrics_acc module.fixed_labels_parameters_metrics()
#       @implemented_optional_functions_acc {:fixed_labels_parameters_metrics, module, true}
#     else
#       @implemented_optional_functions_acc {:fixed_labels_parameters_metrics, module, false}
#     end
#   end

#   flat_unique = fn list -> list |> List.flatten() |> Enum.uniq() end
#   @aggregations @aggregations_acc |> then(flat_unique)
#   @incomplete_metrics @incomplete_metrics_acc |> then(flat_unique)
#   @free_metrics @free_metrics_acc |> then(flat_unique)
#   @restricted_metrics @restricted_metrics_acc |> then(flat_unique)
#   @fixed_labels_parameters_metrics @fixed_labels_parameters_metrics_acc |> then(flat_unique)

#   @timeseries_metric_module_mapping @timeseries_metric_module_mapping_acc |> then(flat_unique)
#   @table_metric_module_mapping @table_metric_module_mapping_acc |> then(flat_unique)
#   @histogram_metric_module_mapping @histogram_metric_module_mapping_acc |> then(flat_unique)

#   # Convert a list of maps to a single map with metric-module key-value pairs
#   metric_module_map = fn list -> Enum.into(list, %{}, &{&1.metric, &1.module}) end
#   @histogram_metric_to_module_map @histogram_metric_module_mapping |> then(metric_module_map)
#   @table_metric_to_module_map @table_metric_module_mapping |> then(metric_module_map)
#   @timeseries_metric_to_module_map @timeseries_metric_module_mapping
#                                    |> then(metric_module_map)

#   @metric_module_mapping (@histogram_metric_module_mapping ++
#                             @timeseries_metric_module_mapping ++ @table_metric_module_mapping)
#                          |> Enum.uniq()

#   @metric_to_module_map @metric_module_mapping |> Enum.into(%{}, &{&1.metric, &1.module})

#   # Convert a list of maps to one single map by merging all the elements
#   reduce_merge = fn list -> Enum.reduce(list, %{}, &Map.merge(&2, &1)) end
#   @aggregations_per_metric @aggregations_per_metric_acc |> then(reduce_merge)
#   @min_plan_map @min_plan_map_acc |> then(reduce_merge)
#   @access_map @access_map_acc |> then(reduce_merge)
#   @required_selectors_map @required_selectors_map_acc
#                           |> then(reduce_merge)

#   @implemented_optional_functions Enum.reduce(
#                                     @implemented_optional_functions_acc,
#                                     %{},
#                                     fn {module, fun, bool}, acc ->
#                                       Map.put(acc, {module, fun}, bool)
#                                     end
#                                   )
#   # the JSON files can define `"access": "free"`
#   # or `"access": {"historical": "free", "realtime": "restricted"}`
#   # both are resolved to a map where the realtime and historical restrictions
#   # are explicitly stated
#   resolve_restrictions = fn
#     restrictions when is_map(restrictions) ->
#       restrictions

#     restriction when restriction in [:free, :restricted] ->
#       %{"historical" => restriction, "realtime" => restriction}
#   end

#   @access_map Enum.into(@access_map, %{}, fn {metric, restrictions} ->
#                 {metric, resolve_restrictions.(restrictions)}
#               end)
#   @metrics Enum.map(@metric_module_mapping, & &1.metric)
#   @timeseries_metrics Enum.map(@timeseries_metric_module_mapping, & &1.metric)
#   @histogram_metrics Enum.map(@histogram_metric_module_mapping, & &1.metric)

#   @metrics_mapset MapSet.new(@metrics)
#   @timeseries_metrics_mapset MapSet.new(@timeseries_metrics)
#   @histogram_metrics_mapset MapSet.new(@histogram_metrics)

#   @table_metrics Enum.map(@table_metric_module_mapping, & &1.metric)
#   @table_metrics_mapset MapSet.new(@table_metrics)

#   @deprecated_metrics_map Enum.reduce(@deprecated_metrics_acc, %{}, &Map.merge(&1, &2))
#                           |> Enum.reject(&match?({_, nil}, &1))
#                           |> Map.new()

#   @soft_deprecated_metrics_map Enum.reduce(@soft_deprecated_metrics_acc, %{}, &Map.merge(&1, &2))
#                                |> Enum.reject(&match?({_, nil}, &1))
#                                |> Map.new()

#   # Do not remove deprecated metrics from the deprecated_metrics_map, as it
#   # will just become empty and unusable
#   def deprecated_metrics_map(),
#     do: @deprecated_metrics_map |> transform(remove_hard_deprecated: false)

#   def soft_deprecated_metrics_map(), do: @soft_deprecated_metrics_map |> transform()
#   def access_map(), do: @access_map |> transform()
#   def aggregations_per_metric(), do: @aggregations_per_metric |> transform()
#   def aggregations(), do: @aggregations |> transform()
#   def incomplete_metrics(), do: @incomplete_metrics |> transform()
#   def free_metrics(), do: @free_metrics |> transform()
#   def histogram_metric_module_mapping(), do: @histogram_metric_module_mapping |> transform()
#   def histogram_metric_to_module_map(), do: @histogram_metric_to_module_map |> transform()
#   def histogram_metrics_mapset(), do: @histogram_metrics_mapset |> transform()
#   def histogram_metrics(), do: @histogram_metrics |> transform()
#   def metric_module_mapping(), do: @metric_module_mapping |> transform()
#   def metric_modules(), do: @compile_time_ready_metric_modules |> transform()
#   def metric_to_module_map(), do: @metric_to_module_map |> transform()
#   def metrics_mapset(), do: @metrics_mapset |> transform()
#   def metrics(), do: @metrics |> transform()
#   def min_plan_map(), do: @min_plan_map |> transform()
#   def restricted_metrics(), do: @restricted_metrics |> transform()
#   def table_metrics(), do: @table_metrics |> transform()
#   def fixed_labels_parameters_metrics(), do: @fixed_labels_parameters_metrics |> transform()
#   def table_metrics_mapset(), do: @table_metrics_mapset |> transform()
#   def table_metric_module_mapping(), do: @table_metric_module_mapping |> transform()
#   def table_metric_to_module_map(), do: @table_metric_to_module_map |> transform()
#   def timeseries_metric_module_mapping(), do: @timeseries_metric_module_mapping |> transform()
#   def timeseries_metric_to_module_map(), do: @timeseries_metric_to_module_map |> transform()
#   def timeseries_metrics_mapset(), do: @timeseries_metrics_mapset |> transform()
#   def timeseries_metrics(), do: @timeseries_metrics |> transform()
#   def required_selectors_map(), do: @required_selectors_map |> transform()
#   def implemented_optional_functions(), do: @implemented_optional_functions

#   # Private functions

#   defp transform(metrics, opts \\ []) do
#     # The `remove_hard_deprecated/1` function is used to completely remove
#     # hard deprecated metrics. The `deprecated_metrics_map` contains the metric
#     # as a key and a datetime as a value. If the current time is after that value,
#     # the metric is excluded
#     metrics
#     |> then(fn metrics ->
#       if Keyword.get(opts, :remove_hard_deprecated, true),
#         do: remove_hard_deprecated(metrics),
#         else: metrics
#     end)
#   end

#   defp remove_hard_deprecated(metrics) when is_list(metrics) do
#     now = DateTime.utc_now()

#     Enum.reject(metrics, fn metric ->
#       hard_deprecate_after = Map.get(@deprecated_metrics_map, metric)
#       not is_nil(hard_deprecate_after) and DateTime.compare(hard_deprecate_after, now) == :lt
#     end)
#   end

#   defp remove_hard_deprecated(%MapSet{} = metrics) do
#     now = DateTime.utc_now()

#     MapSet.reject(metrics, fn metric ->
#       hard_deprecate_after = Map.get(@deprecated_metrics_map, metric)
#       not is_nil(hard_deprecate_after) and DateTime.compare(hard_deprecate_after, now) == :lt
#     end)
#   end

#   defp remove_hard_deprecated(metrics) when is_map(metrics) do
#     now = DateTime.utc_now()

#     Map.reject(metrics, fn {metric, _} ->
#       hard_deprecate_after = Map.get(@deprecated_metrics_map, metric)
#       not is_nil(hard_deprecate_after) and DateTime.compare(hard_deprecate_after, now) == :lt
#     end)
#   end
# end
