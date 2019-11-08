defmodule Sanbase.Clickhouse.Metric.FileHandler do
  @moduledoc false

  defmodule Helper do
    def name_to_field_map(map, field, transform_fn \\ fn x -> x end) do
      map
      |> Enum.map(fn
        %{"name" => name, ^field => value} ->
          {name, transform_fn.(value)}
      end)
      |> Map.new()
    end
  end

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

  @metrics_data_type_map Helper.name_to_field_map(@metrics_json, "data_type", &String.to_atom/1)
  @name_to_column_map Helper.name_to_field_map(@metrics_json, "metric")
  @access_map Helper.name_to_field_map(@metrics_json, "access", &String.to_atom/1)
  @table_map Helper.name_to_field_map(@metrics_json, "table")
  @aggregation_map Helper.name_to_field_map(@metrics_json, "aggregation", &String.to_atom/1)
  @min_interval_map Helper.name_to_field_map(@metrics_json, "min_interval")
  @human_readable_name_map Helper.name_to_field_map(@metrics_json, "human_readable_name")
  @metric_version_map Helper.name_to_field_map(@metrics_json, "version")

  @metrics_list @metrics_json |> Enum.map(fn %{"name" => name} -> name end)
  @metrics_mapset MapSet.new(@metrics_list)

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

  def metrics_label_map(), do: @metrics_label_map

  def metrics_with_access(level) when level in [:free, :restricted] do
    @access_map
    |> Enum.filter(fn {_metric, access_level} -> access_level == level end)
    |> Keyword.keys()
  end

  def metrics_with_data_type(type) do
    @metrics_data_type_map
    |> Enum.filter(fn {_metric, data_type} -> data_type == type end)
    |> Keyword.keys()
  end

  # Private functions
end
