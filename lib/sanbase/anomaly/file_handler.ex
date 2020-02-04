defmodule Sanbase.Anomaly.FileHandler do
  @moduledoc false

  defmodule Helper do
    def name_to_field_map(map, field, transform_fn \\ fn x -> x end) do
      map
      |> Enum.map(fn
        %{"name" => name, ^field => value} ->
          {name, transform_fn.(value)}

        _ ->
          nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()
    end

    def fields_to_name_map(map, fields) do
      map
      |> Enum.into(
        %{},
        fn %{"name" => name} = elem ->
          {Map.take(elem, fields), name}
        end
      )
    end
  end

  # Structure
  #  This JSON file contains a list of anoma;ies available in ClickHouse.
  #  For every anomaly we have:
  #  - metric - the metric on top of which the anomaly is calculated
  #  - access - whether the anomaly is completely free or some time restrictions
  #    should be applied
  #  - aggregation - the default aggregation that is applied to combine the values
  #    if the data is queried with interval bigger than 'min_interval'
  #  - min_interval - the minimal interval the data is available for
  #  - table - the table name in ClickHouse where the anomaly is stored

  @anomalies_file "available_anomalies.json"
  @external_resource available_anomalies_file = Path.join(__DIR__, @anomalies_file)
  @anomalies_json File.read!(available_anomalies_file) |> Jason.decode!()
  @aggregations [:any, :sum, :avg, :min, :max, :last, :first, :median, :count]

  @metric_map Helper.name_to_field_map(@anomalies_json, "metric")
  @access_map Helper.name_to_field_map(@anomalies_json, "access", &String.to_atom/1)
  @table_map Helper.name_to_field_map(@anomalies_json, "table")
  @aggregation_map Helper.name_to_field_map(@anomalies_json, "aggregation", &String.to_atom/1)
  @min_interval_map Helper.name_to_field_map(@anomalies_json, "min_interval")
  @human_readable_name_map Helper.name_to_field_map(@anomalies_json, "human_readable_name")
  @model_name_map Helper.name_to_field_map(@anomalies_json, "model_name")
  @data_type_map Helper.name_to_field_map(@anomalies_json, "data_type", &String.to_atom/1)
  @metric_and_model_to_anomaly_map Helper.fields_to_name_map(@anomalies_json, [
                                     "metric",
                                     "model_name"
                                   ])

  @anomalies_list @anomalies_json |> Enum.map(fn %{"name" => name} -> name end)
  @anomalies_mapset MapSet.new(@anomalies_list)

  def aggregations(), do: @aggregations
  def aggregation_map(), do: @aggregation_map
  def access_map(), do: @access_map
  def metric_map(), do: @metric_map
  def anomalies_mapset(), do: @anomalies_mapset
  def min_interval_map(), do: @min_interval_map
  def human_readable_name_map(), do: @human_readable_name_map
  def table_map(), do: @table_map
  def data_type_map(), do: @data_type_map
  def model_name_map(), do: @model_name_map
  def metric_and_model_to_anomaly_map(), do: @metric_and_model_to_anomaly_map

  def anomalies_with_access(level) when level in [:free, :restricted] do
    @access_map
    |> Enum.filter(fn {_anomaly, access_level} -> access_level == level end)
    |> Keyword.keys()
  end
end
