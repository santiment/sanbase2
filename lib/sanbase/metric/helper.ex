defmodule Sanbase.Metric.Helper do
  @metric_modules [
    Sanbase.Clickhouse.Github.MetricAdapter,
    Sanbase.Clickhouse.MetricAdapter,
    Sanbase.SocialData.MetricAdapter,
    Sanbase.Price.MetricAdapter,
    Sanbase.Twitter.MetricAdapter,
    Sanbase.Clickhouse.TopHolders.MetricAdapter,
    Sanbase.Clickhouse.Uniswap.MetricAdapter
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

    @table_metric_module_mapping_acc Enum.map(
                                       module.available_table_metrics(),
                                       fn metric ->
                                         %{metric: metric, module: module}
                                       end
                                     )
  end

  @aggregations List.flatten(@aggregations_acc) |> Enum.uniq()
  @free_metrics List.flatten(@free_metrics_acc) |> Enum.uniq()
  @restricted_metrics List.flatten(@restricted_metrics_acc) |> Enum.uniq()
  @timeseries_metric_module_mapping List.flatten(@timeseries_metric_module_mapping_acc)
                                    |> Enum.uniq()

  @table_metric_module_mapping List.flatten(@table_metric_module_mapping_acc)
                               |> Enum.uniq()

  @histogram_metric_module_mapping List.flatten(@histogram_metric_module_mapping_acc)
                                   |> Enum.uniq()

  @metric_module_mapping (@histogram_metric_module_mapping ++
                            @timeseries_metric_module_mapping ++ @table_metric_module_mapping)
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

  @table_metrics Enum.map(@table_metric_module_mapping, & &1.metric)
  @table_metrics_mapset MapSet.new(@table_metrics)

  def access_map(), do: @access_map
  def aggregations_per_metric(), do: @aggregations_per_metric
  def aggregations(), do: @aggregations
  def free_metrics(), do: @free_metrics
  def histogram_metric_module_mapping(), do: @histogram_metric_module_mapping

  def histogram_metric_to_module_map(),
    do: @histogram_metric_module_mapping |> Enum.into(%{}, &{&1.metric, &1.module})

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

  def table_metric_to_module_map(),
    do: @table_metric_module_mapping |> Enum.into(%{}, &{&1.metric, &1.module})

  def timeseries_metric_module_mapping(), do: @timeseries_metric_module_mapping

  def timeseries_metric_to_module_map(),
    do: @timeseries_metric_module_mapping |> Enum.into(%{}, &{&1.metric, &1.module})

  def timeseries_metrics_mapset(), do: @timeseries_metrics_mapset
  def timeseries_metrics(), do: @timeseries_metrics
end
