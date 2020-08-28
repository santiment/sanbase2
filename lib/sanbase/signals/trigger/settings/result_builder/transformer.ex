defmodule Sanbase.Signal.ResultBuilder.Transformer do
  defmodule Data do
    @derive Jason.Encoder
    defstruct [
      :identifier,
      :current,
      :previous,
      :previous_average,
      :absolute_change,
      :percent_change
    ]

    defimpl String.Chars, for: __MODULE__ do
      def to_string(data), do: data |> Map.from_struct() |> inspect()
    end
  end

  import Sanbase.Math, only: [percent_change: 2]

  @doc ~s"""
  ## Examples
      iex> data = [{"eos", [%{value: 1}, %{value: 2}, %{value: 5}]}]
      ...> Sanbase.Signal.ResultBuilder.Transformer.transform(data, :value)
      [%Sanbase.Signal.ResultBuilder.Transformer.Data{
        identifier: "eos", absolute_change: 3, current: 5, previous: 2, percent_change: 150.0, previous_average: 1.5
      }]

      iex> data = [{"eos", [%{value: 2}, %{value: 2}, %{value: 3}, %{value: 4}]}]
      ...> Sanbase.Signal.ResultBuilder.Transformer.transform(data, :value)
      [%Sanbase.Signal.ResultBuilder.Transformer.Data{
        absolute_change: 1, current: 4, previous: 3, identifier: "eos", percent_change: 33.33, previous_average: 2.33
      }]

      iex> data = []
      ...> Sanbase.Signal.ResultBuilder.Transformer.transform(data, :value)
      []
  """
  def transform(data, value_key) do
    Enum.map(data, fn
      {identifier, [_, _ | _] = values} ->
        [previous, current] = Enum.take(values, -2) |> Enum.map(&Map.get(&1, value_key))
        previous_list = Enum.drop(values, -1) |> Enum.map(&Map.get(&1, value_key))

        previous_average =
          previous_list
          |> Sanbase.Math.average(precision: 2)

        %Data{
          identifier: identifier,
          current: current,
          previous: previous,
          previous_average: previous_average,
          absolute_change: current - previous,
          percent_change: percent_change(previous, current)
        }

      {identifier, [value]} ->
        %Data{
          identifier: identifier,
          current: value,
          previous: nil,
          previous_average: nil,
          absolute_change: nil,
          percent_change: nil
        }
    end)
  end
end
