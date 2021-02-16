defmodule Sanbase.Signal.FileHandler do
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
  #  This JSON file contains a list of signals available in ClickHouse.
  #  For every signal we have:
  #  - signal - the name of the signal
  #  - access - whether the signal is completely free or some time restrictions
  #    should be applied
  #  - aggregation - the default aggregation that is applied to combine the values
  #    if the data is queried with interval bigger than 'min_interval'
  #  - min_interval - the minimal interval the data is available for
  #  - table - the table name in ClickHouse where the signal is stored

  @signals_file "signal_files/available_signals.json"
  @external_resource available_signals_file = Path.join(__DIR__, @signals_file)
  @signals_json File.read!(available_signals_file) |> Jason.decode!()
  @aggregations Sanbase.Metric.SqlQuery.Helper.aggregations()

  @signal_map Helper.name_to_field_map(@signals_json, "signal")
  @access_map Helper.name_to_field_map(@signals_json, "access", &String.to_atom/1)
  @table_map Helper.name_to_field_map(@signals_json, "table")
  @aggregation_map Helper.name_to_field_map(@signals_json, "aggregation", &String.to_atom/1)
  @min_interval_map Helper.name_to_field_map(@signals_json, "min_interval")
  @human_readable_name_map Helper.name_to_field_map(@signals_json, "human_readable_name")
  @data_type_map Helper.name_to_field_map(@signals_json, "data_type", &String.to_atom/1)

  @signals_list @signals_json |> Enum.map(fn %{"name" => name} -> name end)
  @signals_mapset MapSet.new(@signals_list)

  @selectors_map Helper.name_to_field_map(@signals_json, "selectors", fn list ->
                   Enum.map(list, &String.to_atom/1)
                 end)

  def aggregations(), do: @aggregations
  def aggregation_map(), do: @aggregation_map
  def access_map(), do: @access_map
  def signal_map(), do: @signal_map
  def signals_mapset(), do: @signals_mapset
  def min_interval_map(), do: @min_interval_map
  def human_readable_name_map(), do: @human_readable_name_map
  def table_map(), do: @table_map
  def data_type_map(), do: @data_type_map
  def selectors_map(), do: @selectors_map

  def signals_with_access(level) when level in [:free, :restricted] do
    @access_map
    |> Enum.filter(fn {_signal, access_level} -> access_level == level end)
    |> Enum.map(&elem(&1, 0))
  end
end
