defmodule Sanbase.Clickhouse.Metric.FileHandler do
  @metrics_file "available_v2_metrics.json"
  @external_resource available_metrics_file = Path.join(__DIR__, @metrics_file)

  @metrics_json File.read!(available_metrics_file) |> Jason.decode!()

  @metrics_list @metrics_json
                |> Enum.flat_map(fn
                  %{"alias" => metric_alias, "metric" => metric} -> [metric, metric_alias]
                  %{"metric" => metric} -> [metric]
                end)

  @metrics_mapset MapSet.new(@metrics_list)

  @access_map @metrics_json
              |> Enum.flat_map(fn
                %{"alias" => metric_alias, "metric" => metric, "access" => access} ->
                  [{metric, String.to_atom(access)}, {metric_alias, String.to_atom(access)}]

                %{"metric" => metric, "access" => access} ->
                  [{metric, String.to_atom(access)}]
              end)
              |> Map.new()

  @table_map @metrics_json
             |> Enum.flat_map(fn
               %{"alias" => metric_alias, "metric" => metric, "table" => table} ->
                 [{metric, table}, {metric_alias, table}]

               %{"metric" => metric, "table" => table} ->
                 [{metric, table}]
             end)
             |> Map.new()

  @aggregation_map @metrics_json
                   |> Enum.flat_map(fn
                     %{"alias" => metric_alias, "metric" => metric, "aggregation" => aggregation} ->
                       [
                         {metric, String.to_atom(aggregation)},
                         {metric_alias, String.to_atom(aggregation)}
                       ]

                     %{"metric" => metric, "aggregation" => aggregation} ->
                       [{metric, String.to_atom(aggregation)}]
                   end)
                   |> Map.new()

  @min_interval_map @metrics_json
                    |> Enum.flat_map(fn
                      %{
                        "alias" => metric_alias,
                        "metric" => metric,
                        "min_interval" => min_interval
                      } ->
                        [{metric, min_interval}, {metric_alias, min_interval}]

                      %{"metric" => metric, "min_interval" => min_interval} ->
                        [{metric, min_interval}]
                    end)
                    |> Map.new()

  def access_map(), do: @access_map
  def table_map(), do: @table_map
  def metrics_mapset(), do: @metrics_mapset
  def aggregation_map(), do: @aggregation_map
  def min_interval_map(), do: @min_interval_map

  def metrics_with_access(level) when level in [:free, :restricted] do
    @access_map
    |> Enum.filter(fn {_m, a} -> a == level end)
    |> Keyword.keys()
  end
end
