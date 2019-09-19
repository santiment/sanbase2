defmodule Sanbase.Signal.ResultBuilder.Transformer do
  import Sanbase.Math, only: [percent_change: 2]

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
        percent_change: percent_change(previous_average, current),
        data: Sanbase.Utils.Transform.rename_map_keys(data, old_key: value_key, new_key: :value),
        value_key: value_key
      }
    end)
  end

  @doc ~s"""
  For every `{slug, values}` tuple in the list, calculate the absolute value change
  of the last item compared to the previous value.

  ## Examples
      iex> data = [{"eos", [%{value: 1}, %{value: 2}]}]
      ...> Sanbase.Signal.ResultBuilder.Transformer.transform_absolute_change(data, :value)
      [%{current: 2, absolute_change: 1, previous: 1, slug: "eos"}]

      iex> data = [{"eos", [%{value: 2}, %{value: 2}, %{value: 3}, %{value: 4}]}]
      ...> Sanbase.Signal.ResultBuilder.Transformer.transform_absolute_change(data, :value)
      [%{current: 4, absolute_change: 1, previous: 3, slug: "eos"}]
  """
  @spec transform_absolute_change(list({String.t(), list()}), atom()) ::
          list(%{
            required(:slug) => String.t(),
            required(:current) => number(),
            required(:previous) => number(),
            required(:absolute_change) => number()
          })
  def transform_absolute_change(data, value_key) do
    Enum.map(data, fn {slug, values} ->
      [previous, current] = Enum.take(values, -2) |> Enum.map(&Map.get(&1, value_key))

      %{
        slug: slug,
        current: current,
        previous: previous,
        absolute_change: current - previous
      }
    end)
  end

  @doc ~s"""
  For every `{slug, values}` tuple in the list, calculate the percent change
  of the last item compared to the average the all the previous elements. In the
  case of just 2 elements it calculates the percent change the lead from the
  previous to the current value

  ## Examples
      iex> data = [{"eos", [%{value: 1}, %{value: 2}]}]
      ...> Sanbase.Signal.ResultBuilder.Transformer.transform_percent_change(data, :value)
      [%{current: 2, percent_change: 100.0, previous_average: 1.0, slug: "eos"}]

      iex> data = [{"eos", [%{value: 1}, %{value: 2}, %{value: 1}, %{value: 4}]}]
      ...> Sanbase.Signal.ResultBuilder.Transformer.transform_percent_change(data, :value)
      [%{current: 4, percent_change: 200.75, previous_average: 1.33, slug: "eos"}]
  """
  @spec transform_percent_change(list({String.t(), list(map())}), atom()) ::
          list(%{
            required(:slug) => String.t(),
            required(:current) => number(),
            required(:previous_average) => number(),
            required(:percent_change) => number()
          })
  def transform_percent_change(data, value_key) do
    Enum.map(data, fn {slug, values} ->
      # `current` is the last element, `previous_list` is # the list of all other elements
      # In case of just 2 elements, it is calculating the percent change
      # between the 2 elements
      {current, previous_list} =
        values
        |> Enum.map(&Map.get(&1, value_key))
        |> List.pop_at(-1)

      previous_average =
        previous_list
        |> Sanbase.Math.average(precision: 2)

      %{
        slug: slug,
        current: current,
        previous_average: previous_average,
        percent_change: percent_change(previous_average, current)
      }
    end)
  end

  @doc ~s"""
  For every `{slug, values}` tuple in the list, calculate the absolute value change
  of the last item compared to the previous value.

  ## Examples
      iex> data = [{"eos", [%{value: 1}, %{value: 2}]}]
      ...> Sanbase.Signal.ResultBuilder.Transformer.transform_absolute_change(data, :value)
      [%{current: 2, absolute_change: 1, previous: 1, slug: "eos"}]

      iex> data = [{"eos", [%{value: 2}, %{value: 2}, %{value: 3}, %{value: 4}]}]
      ...> Sanbase.Signal.ResultBuilder.Transformer.transform_absolute_change(data, :value)
      [%{current: 4, absolute_change: 1, previous: 3, slug: "eos"}]
  """
  def transform_get_last(data, value_key) do
    Enum.map(data, fn {slug, values} ->
      %{^value_key => last} = List.last(values)
      %{slug: slug, current: last}
    end)
  end
end
