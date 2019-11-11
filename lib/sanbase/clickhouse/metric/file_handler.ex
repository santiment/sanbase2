defmodule Sanbase.Clickhouse.Metric.FileHandler do
  @moduledoc false

  # Structure
  #  This JSON file contains a list of metrics available in ClickHouse.
  #  For every metric we have:
  #  metric - the original metric name, the very same that is used in the
  #  ClickHouse metric_metadata table
  #  alias - the name we are exposing the metric from the API. It is a more
  #  access - whether the metric is completely free or some time restrictions
  #  should be applied
  #  user-friendly name than the metric name
  #  aggregation - the default aggregation that is applied to combine the values
  #  if the data is queried with interval bigger than 'min_interval'
  #  min-interval - the minimal interval the data is available for
  #  table - the table name in ClickHouse where the metric is stored
  # Orderig
  #  The metrics order in this list is not important. For consistency and
  #  to be easy-readable, the same metric with different time-bound are packed
  #  together. In descending order we have the time-bound from biggest to
  #  smallest.
  #  `time-bound` means that the metric is calculated by taking into account
  #  only the coins/tokens that moved in the past N days/years
  @metrics_file "available_v2_metrics.json"
  @external_resource available_metrics_file = Path.join(__DIR__, @metrics_file)

  @metrics_json File.read!(available_metrics_file) |> Jason.decode!()

  @metrics_list @metrics_json
                |> Enum.flat_map(fn
                  %{"alias" => metric_alias, "metric" => metric} -> [metric, metric_alias]
                  %{"metric" => metric} -> [metric]
                end)
  @aggregations [:any, :sum, :avg, :min, :max, :last, :first, :median]

  @metrics_public_name_data_type_map @metrics_json
                                     |> Enum.map(fn
                                       %{"alias" => metric_alias, "data_type" => data_type} ->
                                         {metric_alias, data_type}

                                       %{"metric" => metric, "data_type" => data_type} ->
                                         {metric, data_type}
                                     end)
                                     |> Map.new(fn {metric, data_type} ->
                                       {metric, String.to_atom(data_type)}
                                     end)

  @metrics_data_type_map @metrics_json
                         |> Enum.flat_map(fn
                           %{
                             "metric" => metric,
                             "alias" => metric_alias,
                             "data_type" => data_type
                           } ->
                             [{metric, data_type}, {metric_alias, data_type}]

                           %{"metric" => metric, "data_type" => data_type} ->
                             [{metric, data_type}]
                         end)
                         |> Map.new(fn {metric, data_type} ->
                           {metric, String.to_existing_atom(data_type)}
                         end)

  @metrics_mapset MapSet.new(@metrics_list)
  @name_to_column_map @metrics_json
                      |> Enum.flat_map(fn
                        %{"alias" => metric_alias, "metric" => metric} ->
                          [
                            {metric_alias, metric},
                            {metric, metric}
                          ]

                        %{"metric" => metric} ->
                          [{metric, metric}]
                      end)
                      |> Map.new()

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

  @human_readable_name_map @metrics_json
                           |> Enum.flat_map(fn
                             %{
                               "alias" => metric_alias,
                               "metric" => metric,
                               "human_readable_name" => human_readable_name
                             } ->
                               [
                                 {metric, human_readable_name},
                                 {metric_alias, human_readable_name}
                               ]

                             %{"metric" => metric, "human_readable_name" => human_readable_name} ->
                               [{metric, human_readable_name}]
                           end)
                           |> Map.new()

  @metric_version_map @metrics_json
                      |> Enum.flat_map(fn
                        %{"alias" => metric_alias, "metric" => metric, "version" => version} ->
                          [
                            {metric_alias, version},
                            {metric, version}
                          ]

                        %{"metric" => metric, "version" => version} ->
                          [{metric, version}]
                      end)
                      |> Map.new()

  case Enum.filter(@aggregation_map, fn {_, aggr} -> aggr not in @aggregations end) do
    [] ->
      :ok

    metrics ->
      require(Sanbase.Break, as: Break)

      Break.break("""
      There are metrics defined in the #{@metrics_file} that have not supported aggregation.
      These metrics are: #{inspect(metrics)}
      """)
  end

  def aggregations(), do: @aggregations
  def access_map(), do: @access_map
  def table_map(), do: @table_map
  def metrics_mapset(), do: @metrics_mapset
  def aggregation_map(), do: @aggregation_map
  def min_interval_map(), do: @min_interval_map
  def name_to_column_map(), do: @name_to_column_map
  def human_readable_name_map(), do: @human_readable_name_map

  def metric_version_map(), do: @metric_version_map

  def metrics_data_type_map(), do: @metrics_data_type_map

  def metrics_with_access(level) when level in [:free, :restricted] do
    @access_map
    |> Enum.filter(fn {_metric, access_level} -> access_level == level end)
    |> Keyword.keys()
  end

  def metrics_with_data_type(type) do
    @metrics_public_name_data_type_map
    |> Enum.filter(fn {_metric, data_type} -> data_type == type end)
    |> Keyword.keys()
  end
end
