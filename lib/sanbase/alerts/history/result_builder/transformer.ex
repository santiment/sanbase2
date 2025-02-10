defmodule Sanbase.Alert.History.ResultBuilder.Transformer do
  @moduledoc ~s"""
  Prepare the raw data for checking when the alrt would have fired in the past
  """
  import Sanbase.DateTimeUtils, only: [str_to_days: 1]
  import Sanbase.Math, only: [percent_change: 2]

  @doc ~s"""
  Transform the raw data into data points containing the actual value, the percent
  change and the absolute value change compared to `time_period` before.

  ## Examples
      iex> Sanbase.Alert.History.ResultBuilder.Transformer.transform(
      ...>[ %{value: 1, datetime: ~U[2019-01-01 00:00:00Z]},
      ...>  %{value: 2, datetime: ~U[2019-01-02 00:00:00Z]},
      ...> %{value: 10, datetime: ~U[2019-01-03 00:00:00Z]}],
      ...> "1d", :value)
      [%{absolute_change: 1, datetime: ~U[2019-01-02 00:00:00Z], percent_change: 100.0, current: 2},
      %{absolute_change: 8, datetime: ~U[2019-01-03 00:00:00Z], percent_change: 400.0, current: 10}]
  """
  def transform(raw_data, time_window, value_key) do
    time_window_in_days = Enum.max([str_to_days(time_window), 2])

    raw_data
    |> Enum.chunk_every(time_window_in_days, 1, :discard)
    |> Enum.map(fn chunk ->
      first = List.first(chunk)
      last = List.last(chunk)

      %{
        datetime: last.datetime,
        current: last[value_key],
        percent_change: percent_change(first[value_key], last[value_key]),
        absolute_change: last[value_key] - first[value_key]
      }
    end)
  end
end
