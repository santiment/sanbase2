defmodule Sanbase.Signal.ResultBuilder do
  import Sanbase.Signal.OperationEvaluation

  def build_result_percent(
        data,
        %_trigger_module{operation: operation} = settings,
        payload_fun
      ) do
    payload =
      transform_data_percent(data)
      |> Enum.reduce(%{}, fn %{slug: slug, percent_change: percent_change} = values, acc ->
        case operation_triggered?(percent_change, operation) do
          true ->
            Map.put(
              acc,
              slug,
              payload_fun.(:percent, slug, settings, values)
            )

          false ->
            acc
        end
      end)

    %{
      settings
      | triggered?: payload != %{},
        payload: payload
    }
  end

  def build_result_absolute(
        data,
        %_trigger_module{operation: operation} = settings,
        payload_fun
      ) do
    payload =
      transform_data_absolute(data)
      |> Enum.reduce(%{}, fn %{slug: slug, current: current} = values, acc ->
        case operation_triggered?(current, operation) do
          true ->
            Map.put(acc, slug, payload_fun.(:absolute, slug, settings, values))

          false ->
            acc
        end
      end)

    %{
      settings
      | triggered?: payload != %{},
        payload: payload
    }
  end

  defp transform_data_percent(data, value_key \\ :value) do
    Enum.map(data, fn {slug, values} ->
      # current is the last element, previous_list is the list of all other elements
      {current, previous_list} =
        values
        |> Enum.map(&Map.get(&1, value_key))
        |> List.pop_at(-1)

      previous_avg =
        previous_list
        |> Sanbase.Math.average(precision: 2)

      %{
        slug: slug,
        previous_avg: previous_avg,
        current: current,
        percent_change: percent_change(previous_avg, current)
      }
    end)
  end

  defp transform_data_absolute(data, value_key \\ :value) do
    Enum.map(data, fn {slug, values} ->
      %{value_key => last} = List.last(values)
      %{slug: slug, current: last}
    end)
  end
end
