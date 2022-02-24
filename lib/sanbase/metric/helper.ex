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

  @metric_modules [
    Sanbase.Clickhouse.Github.MetricAdapter,
    Sanbase.Clickhouse.MetricAdapter,
    Sanbase.SocialData.MetricAdapter,
    Sanbase.Price.MetricAdapter,
    Sanbase.Twitter.MetricAdapter,
    Sanbase.Clickhouse.TopHolders.MetricAdapter,
    Sanbase.Clickhouse.Uniswap.MetricAdapter,
    Sanbase.BlockchainAddress.MetricAdapter,
    Sanbase.Contract.MetricAdapter
  ]

  Module.register_attribute(__MODULE__, :aggregations_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :aggregations_per_metric_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :free_metrics_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :restricted_metrics_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :access_map_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :min_plan_map_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :timeseries_metric_module_mapping_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :histogram_metric_module_mapping_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :table_metric_module_mapping_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :required_selectors_map_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :deprecated_metrics_acc, accumulate: true)

  for module <- @metric_modules do
    @required_selectors_map_acc module.required_selectors
    @aggregations_acc module.available_aggregations()
    @free_metrics_acc module.free_metrics()
    @restricted_metrics_acc module.restricted_metrics()
    @access_map_acc module.access_map()
    @min_plan_map_acc module.min_plan_map()

    aggregations_fn = fn metric ->
      {:ok, %{available_aggregations: aggr}} = module.metadata(metric)
      {metric, [nil] ++ aggr}
    end

    @aggregations_per_metric_acc Enum.into(module.available_metrics(), %{}, aggregations_fn)

    @timeseries_metric_module_mapping_acc Enum.map(
                                            module.available_timeseries_metrics(),
                                            fn metric -> %{metric: metric, module: module} end
                                          )

    @histogram_metric_module_mapping_acc Enum.map(
                                           module.available_histogram_metrics(),
                                           fn metric -> %{metric: metric, module: module} end
                                         )

    @table_metric_module_mapping_acc Enum.map(
                                       module.available_table_metrics(),
                                       fn metric -> %{metric: metric, module: module} end
                                     )

    if function_exported?(module, :deprecated_metrics_map, 0),
      do: @deprecated_metrics_acc(module.deprecated_metrics_map)
  end

  flat_unique = fn list -> list |> List.flatten() |> Enum.uniq() end
  @aggregations @aggregations_acc |> then(flat_unique)
  @free_metrics @free_metrics_acc |> then(flat_unique)
  @restricted_metrics @restricted_metrics_acc |> then(flat_unique)
  @timeseries_metric_module_mapping @timeseries_metric_module_mapping_acc |> then(flat_unique)
  @table_metric_module_mapping @table_metric_module_mapping_acc |> then(flat_unique)
  @histogram_metric_module_mapping @histogram_metric_module_mapping_acc |> then(flat_unique)

  # Convert a list of maps to a single map with metric-module key-value pairs
  metric_module_map = fn list -> Enum.into(list, %{}, &{&1.metric, &1.module}) end
  @histogram_metric_to_module_map @histogram_metric_module_mapping |> then(metric_module_map)
  @table_metric_to_module_map @table_metric_module_mapping |> then(metric_module_map)
  @timeseries_metric_to_module_map @timeseries_metric_module_mapping
                                   |> then(metric_module_map)

  @metric_module_mapping (@histogram_metric_module_mapping ++
                            @timeseries_metric_module_mapping ++ @table_metric_module_mapping)
                         |> Enum.uniq()

  @metric_to_module_map @metric_module_mapping |> Enum.into(%{}, &{&1.metric, &1.module})

  # Convert a list of maps to one single map by merging all the elements
  reduce_merge = fn list -> Enum.reduce(list, %{}, &Map.merge(&2, &1)) end
  @aggregations_per_metric @aggregations_per_metric_acc |> then(reduce_merge)
  @min_plan_map @min_plan_map_acc |> then(reduce_merge)
  @access_map @access_map_acc |> then(reduce_merge)
  @required_selectors_map @required_selectors_map_acc
                          |> then(reduce_merge)

  resolve_restrictions = fn
    restrictions when is_map(restrictions) ->
      restrictions

    restriction when restriction in [:restricted, :free] ->
      %{"historical" => restriction, "realtime" => restriction}
  end

  @access_map Enum.into(@access_map, %{}, fn {metric, restrictions} ->
                {metric, resolve_restrictions.(restrictions)}
              end)
  @metrics Enum.map(@metric_module_mapping, & &1.metric)
  @timeseries_metrics Enum.map(@timeseries_metric_module_mapping, & &1.metric)
  @histogram_metrics Enum.map(@histogram_metric_module_mapping, & &1.metric)

  @metrics_mapset MapSet.new(@metrics)
  @timeseries_metrics_mapset MapSet.new(@timeseries_metrics)
  @histogram_metrics_mapset MapSet.new(@histogram_metrics)

  @table_metrics Enum.map(@table_metric_module_mapping, & &1.metric)
  @table_metrics_mapset MapSet.new(@table_metrics)

  @deprecated_metrics_map Enum.reduce(@deprecated_metrics_acc, %{}, &Map.merge(&1, &2))
                          |> Enum.reject(&match?({_, nil}, &1))
                          |> Map.new()

  def access_map(), do: @access_map
  def aggregations_per_metric(), do: @aggregations_per_metric
  def aggregations(), do: @aggregations
  def free_metrics(), do: @free_metrics
  def deprecated_metrics_map(), do: @deprecated_metrics_map
  def histogram_metric_module_mapping(), do: @histogram_metric_module_mapping
  def histogram_metric_to_module_map(), do: @histogram_metric_to_module_map
  def histogram_metrics_mapset(), do: @histogram_metrics_mapset
  def histogram_metrics(), do: @histogram_metrics
  def metric_module_mapping(), do: @metric_module_mapping
  def metric_modules(), do: @metric_modules
  def metric_to_module_map(), do: @metric_to_module_map
  def metrics_mapset(), do: @metrics_mapset
  def metrics(), do: @metrics
  def min_plan_map(), do: @min_plan_map
  def restricted_metrics(), do: @restricted_metrics
  def table_metrics(), do: @table_metrics
  def table_metrics_mapset(), do: @table_metrics_mapset
  def table_metric_module_mapping(), do: @table_metric_module_mapping
  def table_metric_to_module_map(), do: @table_metric_to_module_map
  def timeseries_metric_module_mapping(), do: @timeseries_metric_module_mapping
  def timeseries_metric_to_module_map(), do: @timeseries_metric_to_module_map
  def timeseries_metrics_mapset(), do: @timeseries_metrics_mapset
  def timeseries_metrics(), do: @timeseries_metrics
  def required_selectors_map(), do: @required_selectors_map
end
