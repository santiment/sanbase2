defmodule Sanbase.Signal.FileHandler do
  @moduledoc false

  defmodule Helper do
    import Sanbase.DateTimeUtils, only: [interval_to_str: 1]

    alias Sanbase.TemplateEngine

    require Sanbase.Break, as: Break

    # The selected field is required by default
    # A missing required field will result in a compile time error
    def name_to_field_map(map, field, opts \\ []) do
      Break.if_kw_invalid?(opts, valid_keys: [:transform_fn, :required?])

      transform_fn = Keyword.get(opts, :transform_fn, &Function.identity/1)
      required? = Keyword.get(opts, :required?, true)

      map
      |> Enum.into(%{}, fn
        %{"name" => name, ^field => value} ->
          {name, transform_fn.(value)}

        %{"name" => name} ->
          if required? do
            Break.break("The field \"#{field}\" in the #{Jason.encode!(name)} signal is required")
          else
            {name, nil}
          end
      end)
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

    def resolve_timebound_signals(signal_map, timebound_values) do
      %{
        "name" => name,
        "signal" => signal,
        "human_readable_name" => human_readable_name
      } = signal_map

      timebound_values
      |> Enum.map(fn timebound ->
        params = %{timebound: timebound, timebound_human_readable: interval_to_str(timebound)}

        %{
          signal_map
          | "name" => TemplateEngine.run(name, params: params),
            "signal" => TemplateEngine.run(signal, params: params),
            "human_readable_name" => TemplateEngine.run(human_readable_name, params: params)
        }
      end)
    end

    def expand_timebound_signals(signals_json_pre_timebound_expand) do
      Enum.flat_map(
        signals_json_pre_timebound_expand,
        fn signal ->
          case Map.get(signal, "timebound") do
            nil ->
              [signal]

            timebound_values ->
              resolve_timebound_signals(signal, timebound_values)
          end
        end
      )
    end

    def atomize_access_level_value(access) when is_binary(access),
      do: String.to_existing_atom(access)

    def atomize_access_level_value(access) when is_map(access) do
      Enum.into(access, %{}, fn {k, v} -> {k, String.to_existing_atom(v)} end)
    end

    def resolve_access_level(access) when is_atom(access), do: access

    def resolve_access_level(access) when is_map(access) do
      case access do
        %{"historical" => "FREE", "realtime" => "FREE"} -> "FREE"
        _ -> :restricted
      end
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
  @signals_json_pre_timebound_expand File.read!(available_signals_file) |> Jason.decode!()
  @signals_json Helper.expand_timebound_signals(@signals_json_pre_timebound_expand)

  @aggregations [:none] ++ Sanbase.Metric.SqlQuery.Helper.aggregations()
  @signal_map Helper.name_to_field_map(@signals_json, "signal", required?: true)
  @name_to_signal_map @signal_map
  @signal_to_name_map Map.new(@name_to_signal_map, fn {k, v} -> {v, k} end)
  @access_map Helper.name_to_field_map(@signals_json, "access",
                transform_fn: &Helper.atomize_access_level_value/1
              )
  @table_map Helper.name_to_field_map(@signals_json, "table", required?: true)
  @aggregation_map Helper.name_to_field_map(@signals_json, "aggregation",
                     transform_fn: &String.to_atom/1
                   )
  @min_interval_map Helper.name_to_field_map(@signals_json, "min_interval", required?: true)
  @human_readable_name_map Helper.name_to_field_map(@signals_json, "human_readable_name")
  @data_type_map Helper.name_to_field_map(@signals_json, "data_type",
                   transform_fn: &String.to_atom/1
                 )

  @signals_list @signals_json |> Enum.map(fn %{"name" => name} -> name end)
  @signals_mapset MapSet.new(@signals_list)
  @min_plan_map Helper.name_to_field_map(@signals_json, "min_plan",
                  transform_fn: fn plan_map ->
                    Enum.into(plan_map, %{}, fn {k, v} -> {k, String.upcase(v)} end)
                  end
                )

  @signals_data_type_map Helper.name_to_field_map(@signals_json, "data_type",
                           transform_fn: &String.to_atom/1
                         )

  @selectors_map Helper.name_to_field_map(@signals_json, "selectors",
                   transform_fn: fn list ->
                     Enum.map(list, &String.to_atom/1)
                   end
                 )

  Enum.group_by(
    @signals_json_pre_timebound_expand,
    fn signal -> {signal["signal"], signal["data_type"]} end
  )
  |> Map.values()
  |> Enum.filter(fn group -> Enum.count(group) > 1 end)
  |> Enum.each(fn duplicate_signals ->
    Break.break("""
      Duplicate signals found: #{inspect(duplicate_signals)}
    """)
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
  def min_plan_map(), do: @min_plan_map
  def selectors_map(), do: @selectors_map
  def name_to_signal_map(), do: @name_to_signal_map
  def signal_to_name_map(), do: @signal_to_name_map

  def signals_with_access(level) when level in [:free, :restricted] do
    @access_map
    |> Enum.filter(fn {_signal, restrictions} ->
      Helper.resolve_access_level(restrictions) === level
    end)
    |> Enum.map(&elem(&1, 0))
  end

  def signals_with_data_type(type) do
    @signals_data_type_map
    |> Enum.filter(fn {_signal, data_type} -> data_type == type end)
    |> Enum.map(&elem(&1, 0))
  end
end
