defmodule Sanbase.Signals.History.Utils do
  def moving_average_excluding_last(list, period, key)
      when is_list(list) and is_integer(period) and period > 0 do
    result =
      list
      |> Enum.chunk_every(period, 1, :discard)
      |> Enum.map(fn elems ->
        value = elems |> List.last() |> Map.get(key)
        {datetime, average} = average(elems, key)

        %{
          datetime: datetime,
          average: average
        }
        |> Map.put(key, value)
      end)

    {:ok, result}
  end

  def merge_chunks_by_datetime(initial_points, points_override) do
    initial_points
    |> Enum.map(fn initial_point ->
      Enum.find(points_override, initial_point, fn po ->
        DateTime.compare(initial_point.datetime, po.datetime) == :eq
      end)
    end)
  end

  # private functions

  defp average([], _), do: 0

  defp average(l, key) when is_list(l) do
    values = Enum.map(l, fn item -> Map.get(item, key) end) |> Enum.drop(-1)
    %{datetime: datetime} = List.last(l)
    average = Enum.sum(values) / length(values)

    {datetime, average}
  end
end
