defmodule Sanbase.Signal.ResultBuilder.Transformer do
  import Sanbase.Math, only: [percent_change: 2]

  @doc ~s"""
  ## Examples
      iex> data = [{"eos", [%{value: 1}, %{value: 2}, %{value: 5}]}]
      ...> Sanbase.Signal.ResultBuilder.Transformer.transform(data, :value)
      [%{slug: "eos", absolute_change: 3, current: 5, previous: 2, percent_change: 233.33, previous_average: 1.5}]

      iex> data = [{"eos", [%{value: 2}, %{value: 2}, %{value: 3}, %{value: 4}]}]
      ...> Sanbase.Signal.ResultBuilder.Transformer.transform(data, :value)
      [%{absolute_change: 1, current: 4, previous: 3, slug: "eos", percent_change: 71.67, previous_average: 2.33}]

      iex> data = []
      ...> Sanbase.Signal.ResultBuilder.Transformer.transform(data, :value)
      []
  """
  def transform(data, value_key) do
    Enum.map(data, fn {slug, values} ->
      [previous, current] = Enum.take(values, -2) |> Enum.map(&Map.get(&1, value_key))
      previous_list = Enum.drop(values, -1) |> Enum.map(&Map.get(&1, value_key))
      previous_average = previous_list |> Sanbase.Math.average(precision: 2)

      %{
        slug: slug,
        current: current,
        previous: previous,
        previous_average: previous_average,
        absolute_change: current - previous,
        percent_change: percent_change(previous_average, current)
      }
    end)
  end
end
