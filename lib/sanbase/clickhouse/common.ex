defmodule Sanbase.Clickhouse.Common do
  alias Sanbase.DateTimeUtils

  def convert_historical_balance_result({:ok, []}, _, _, _), do: []

  def convert_historical_balance_result({:ok, result}, from_datetime, to_datetime, interval) do
    from_datetime_unix = DateTime.to_unix(from_datetime)
    to_datetime_unix = DateTime.to_unix(to_datetime)
    interval_points = div(to_datetime_unix - from_datetime_unix, interval) + 1

    intervals =
      from_datetime_unix
      |> Stream.iterate(fn dt_unix -> dt_unix + interval end)
      |> Enum.take(interval_points)

    initial_intervals = intervals |> Enum.map(fn int -> {int, 0} end) |> Enum.into(%{})
    filled_intervals = fill_intervals_with_balance(intervals, result)

    calculate_balances_for_intervals(initial_intervals, filled_intervals)
  end

  def convert_historical_balance_result(_, _, _, _), do: []

  def calculate_balances_for_intervals(initial_intervals, filled_intervals) do
    initial_intervals
    |> Map.merge(filled_intervals)
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map(fn {dt, value} ->
      %{
        datetime: DateTime.from_unix!(dt),
        balance: value
      }
    end)
  end

  defp fill_intervals_with_balance(intervals, balances) do
    {_, last_balance} = balances |> List.last()

    for int <- intervals,
        {dt, balance} <- balances do
      if int >= dt do
        {int, balance}
      else
        {int, nil}
      end
    end
    |> Enum.filter(fn {_, v} -> v != nil end)
    |> List.update_at(-1, fn {k, _} -> {k, last_balance} end)
    |> Enum.into(%{})
  end

  def datetime_rounding_for_interval(interval) do
    if interval < DateTimeUtils.compound_duration_to_seconds("1d") do
      "toStartOfHour(dt)"
    else
      "toStartOfDay(dt)"
    end
  end
end
