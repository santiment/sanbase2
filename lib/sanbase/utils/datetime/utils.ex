defmodule Sanbase.DateTimeUtils do
  def seconds_to_human_readable(seconds) do
    seconds
    |> Timex.Duration.from_seconds()
    |> Elixir.Timex.Format.Duration.Formatters.Humanized.format()
  end

  def truncate_datetimes(%{} = map, precision \\ :second) do
    Enum.into(map, %{}, fn
      {k, %DateTime{} = dt} -> {k, DateTime.truncate(dt, precision)}
      {k, %NaiveDateTime{} = dt} -> {k, NaiveDateTime.truncate(dt, precision)}
      {k, v} -> {k, v}
    end)
  end

  def time_in_range?(%Time{} = time, %Time{} = from, %Time{} = to) do
    case Time.compare(from, to) do
      :eq ->
        false

      :gt ->
        # from is bigger than to, intervals like: 23:59:00 - 00:01:00
        time_in_range?(time, from, ~T[23:59:59.99999]) or time_in_range?(time, ~T[00:00:00], to)

      :lt ->
        # from is smaller than to, intervals like 13:00:00 - 13:05:00
        Time.compare(time, from) != :lt and Time.compare(time, to) != :gt
    end
  end

  @doc ~s"""
  Sleep until `datetime` if and only if it is in the future.
  """
  @spec sleep_until(DateTime.t()) :: :ok
  def sleep_until(%DateTime{} = datetime) do
    case DateTime.diff(datetime, DateTime.utc_now(), :millisecond) do
      sleep_ms when is_integer(sleep_ms) and sleep_ms > 0 ->
        Process.sleep(sleep_ms)

      _ ->
        :ok
    end
  end

  def after_interval(interval, datetime \\ DateTime.utc_now()) when is_binary(interval) do
    str_to_sec(interval) |> seconds_after(datetime)
  end

  def seconds_after(seconds, datetime \\ DateTime.utc_now()) do
    datetime
    |> Timex.shift(seconds: seconds)
  end

  def days_after(days, datetime \\ DateTime.utc_now()) do
    seconds_after(days * 60 * 60 * 24, datetime)
  end

  def seconds_ago(seconds, datetime \\ DateTime.utc_now()) do
    datetime
    |> Timex.shift(seconds: -seconds)
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

  def str_to_hours(interval) do
    str_to_sec(interval) |> Integer.floor_div(3600)
  end

  def date_to_datetime(date) do
    {:ok, datetime, _} = (Date.to_iso8601(date) <> "T00:00:00Z") |> DateTime.from_iso8601()

    datetime
  end

  def str_to_sec(interval) do
    {int_interval, duration_index} = Integer.parse(interval)

    case duration_index do
      "ns" -> div(int_interval, 1_000_000_000)
      "ms" -> div(int_interval, 1_000_000)
      "s" -> int_interval
      "m" -> int_interval * 60
      "h" -> int_interval * 60 * 60
      "d" -> int_interval * 24 * 60 * 60
      "w" -> int_interval * 7 * 24 * 60 * 60
    end
  end

  def str_to_days(interval) do
    interval_in_seconds = str_to_sec(interval)
    one_day_in_seconds = 3600 * 24

    div(interval_in_seconds, one_day_in_seconds)
  end

  def interval_to_str(interval) do
    {int_interval, duration_index} = Integer.parse(interval)

    case duration_index do
      "ns" -> "#{int_interval} nanosecond(s)"
      "ms" -> "#{int_interval} millisecond(s)"
      "s" -> "#{int_interval} second(s)"
      "m" -> "#{int_interval} minute(s)"
      "h" -> "#{int_interval} hour(s)"
      "d" -> "#{int_interval} day(s)"
      "w" -> "#{int_interval} week(s)"
    end
  end

  def valid_compound_duration?(value) do
    case Integer.parse(value) do
      {int, string} when is_integer(int) and string in ["ns", "s", "m", "h", "d", "w"] -> true
      _ -> false
    end
  end

  def from_erl(erl_datetime) do
    with {:ok, naive_dt} <- NaiveDateTime.from_erl(erl_datetime),
         {:ok, datetime} <- DateTime.from_naive(naive_dt, "Etc/UTC") do
      {:ok, datetime}
    end
  end

  def from_erl!(erl_datetime) do
    case from_erl(erl_datetime) do
      {:ok, datetime} -> datetime
      {:error, error} -> raise(error)
    end
  end

  def from_iso8601!(datetime_str) when is_binary(datetime_str) do
    {:ok, datetime, _} = DateTime.from_iso8601(datetime_str)
    datetime
  end

  def from_iso8601!(%DateTime{} = dt), do: dt

  def from_iso8601_to_unix!(datetime_str) do
    datetime_str
    |> from_iso8601!()
    |> DateTime.to_unix()
  end

  def time_from_iso8601!(time_str) when is_binary(time_str) do
    {:ok, time} = Time.from_iso8601(time_str)
    time
  end

  def time_from_8601!(%Time{} = time), do: time

  def valid_interval_string?(interval_string) when not is_binary(interval_string) do
    {:error, "The provided string #{interval_string} is not a valid string interval"}
  end

  def valid_interval_string?(interval_string) when is_binary(interval_string) do
    if Regex.match?(~r/^\d+[smhdw]{1}$/, interval_string) do
      true
    else
      {:error, "The provided string #{interval_string} is not a valid string interval"}
    end
  end

  @doc ~s"""
  Round the given datetime to the nearest datetime, which in its UNIX
  representation is divisible by `seconds`

  This function is used to bucket all datetimes in a given interval to a single
  datetime, usable in cache key construction
  """
  def round_datetime(datetime, seconds \\ 300) do
    DateTime.to_unix(datetime)
    |> div(seconds)
    |> Kernel.*(seconds)
    |> DateTime.from_unix!()
  end
end
