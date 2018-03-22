defmodule Sanbase.DateTimeUtils do
  def seconds_after(seconds, datetime \\ DateTime.utc_now()) do
    datetime
    |> DateTime.to_unix()
    |> Kernel.+(seconds)
    |> DateTime.from_unix!()
  end

  def days_after(days, datetime \\ DateTime.utc_now()) do
    seconds_after(days * 60 * 60 * 24, datetime)
  end

  def seconds_ago(seconds) do
    DateTime.utc_now()
    |> DateTime.to_unix()
    |> Kernel.-(seconds)
    |> DateTime.from_unix!()
  end

  def minutes_ago(minutes) do
    seconds_ago(minutes * 60)
  end

  def hours_ago(hours) do
    seconds_ago(hours * 60 * 60)
  end

  def days_ago(days) do
    seconds_ago(days * 60 * 60 * 24)
  end

  # Interval should be an integer followed by one of: s, m, h, d or w
  def str_to_sec(interval) do
    interval_type = String.last(interval)

    String.slice(interval, 0..-2)
    |> String.to_integer()
    |> str_to_sec(interval_type)
  end

  def str_to_hours(interval) do
    str_to_sec(interval) |> Integer.floor_div(3600)
  end

  defp str_to_sec(seconds, "s"), do: seconds
  defp str_to_sec(minutes, "m"), do: minutes * 60
  defp str_to_sec(hours, "h"), do: hours * 60 * 60
  defp str_to_sec(days, "d"), do: days * 60 * 60 * 24
  defp str_to_sec(weeks, "w"), do: weeks * 60 * 60 * 24 * 7

  def datetime_from_date(%Date{} = date, time \\ ~T[00:00:00]) do
    {:ok, naive_datetime} = NaiveDateTime.new(date, time)
    datetime = DateTime.from_naive!(naive_datetime, "Etc/UTC")
  end
end
