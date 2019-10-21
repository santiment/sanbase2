defmodule Sanbase.Signal.History.ResultBuilder.Transformer do
  import Sanbase.Math, only: [percent_change: 2]
  import Sanbase.DateTimeUtils, only: [str_to_days: 1]

  def transform(raw_data, time_window, value_key) do
    time_window_in_days = Enum.max([str_to_days(time_window), 2])

    Enum.chunk_every(raw_data, time_window_in_days, 1, :discard)
    |> Enum.map(fn chunk ->
      first = List.first(chunk)
      last = List.last(chunk)

      %{
        datetime: last.datetime,
        current: last[value_key],
        percent_change: percent_change(first[value_key], last[value_key]),
        absolute_change: first[value_key] - last[value_key]
      }
    end)
  end
end
