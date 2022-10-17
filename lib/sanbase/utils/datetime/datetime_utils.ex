defmodule Sanbase.DateTimeUtils do
  def utc_now_string_to_datetime!("utc_now" <> _ = value) do
    case utc_now_string_to_datetime(value) do
      {:ok, value} -> value
      {:error, error} -> raise(error)
    end
  end

  def utc_now_string_to_datetime("utc_now" <> _ = value) do
    case String.split(value, ~r/\s*-\s*/) do
      ["utc_now"] ->
        {:ok, DateTime.utc_now()}

      ["utc_now", interval] ->
        case valid_compound_duration?(interval) do
          true ->
            dt =
              DateTime.utc_now()
              |> Timex.shift(seconds: -str_to_sec(interval))

            {:ok, dt}

          false ->
            {:error, "The interval part of #{value} is not a valid interval"}
        end

      _ ->
        {:error, "The #{value} datetime string representation is malformed."}
    end
  end

  @doc ~s"""
  Return a human readable representation of a datetime
  """
  def to_human_readable(datetime) do
    datetime
    |> Timex.format!("{0D} {Mshort} {YYYY} {h24}:{m} UTC")
  end

  def seconds_to_human_readable(seconds) do
    seconds
    |> Timex.Duration.from_seconds()
    |> Timex.Format.Duration.Formatters.Humanized.format()
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

  def generate_datetimes_list(from, interval, count) do
    interval_sec = Sanbase.DateTimeUtils.str_to_sec(interval)

    0..(count - 1) |> Enum.map(fn offset -> Timex.shift(from, seconds: interval_sec * offset) end)
  end

  def generate_dates_inclusive(%Date{} = from, %Date{} = to) do
    do_generate_dates_inclusive(from, to, [])
  end

  defp do_generate_dates_inclusive(from, to, acc) do
    case Date.compare(from, to) do
      :gt -> Enum.reverse(acc)
      _ -> do_generate_dates_inclusive(Date.add(from, 1), to, [from | acc])
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

  def before_interval(interval, datetime \\ DateTime.utc_now()) when is_binary(interval) do
    str_to_sec(interval) |> seconds_ago(datetime)
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

  def date_to_datetime(date, opts \\ []) do
    time = Keyword.get(opts, :time, ~T[00:00:00Z]) |> Time.to_iso8601()

    {:ok, datetime, _} = (Date.to_iso8601(date) <> "T" <> time <> "Z") |> DateTime.from_iso8601()

    datetime
  end

  @supported_interval_functions Sanbase.Metric.SqlQuery.Helper.supported_interval_functions()
  @interval_function_to_equal_interval Sanbase.Metric.SqlQuery.Helper.interval_function_to_equal_interval()

  def maybe_str_to_sec(interval) do
    case interval in @supported_interval_functions do
      true -> interval
      false -> str_to_sec(interval)
    end
  end

  # If interval_function is 'toStartOfWeek', 'toStartOfMonth', etc.
  def str_to_sec(interval_function) when interval_function in @supported_interval_functions do
    Map.get(@interval_function_to_equal_interval, interval_function)
    |> str_to_sec()
  end

  def str_to_sec(interval) do
    {int_interval, duration_index} =
      case Integer.parse(interval) do
        {_, _} = result -> result
        :error -> raise(ArgumentError, "The interval #{interval} is not a valid interval")
      end

    case duration_index do
      "ns" -> div(int_interval, 1_000_000_000)
      "ms" -> div(int_interval, 1_000_000)
      "s" -> int_interval
      "m" -> int_interval * 60
      "h" -> int_interval * 60 * 60
      "d" -> int_interval * 24 * 60 * 60
      "w" -> int_interval * 7 * 24 * 60 * 60
      "y" -> int_interval * 365 * 24 * 60 * 60
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
      "ns" -> "#{int_interval} nanosecond"
      "ms" -> "#{int_interval} millisecond"
      "s" -> "#{int_interval} second"
      "m" -> "#{int_interval} minute"
      "h" -> "#{int_interval} hour"
      "d" -> "#{int_interval} day"
      "w" -> "#{int_interval} week"
      "y" -> "#{int_interval} year"
    end
    |> maybe_pluralize_interval(int_interval)
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

  def valid_interval?(interval) do
    _ = str_to_sec(interval)
    true
  rescue
    _ -> false
  end

  @doc ~s"""
  Round the given datetime to the nearest datetime, which in its UNIX
  representation is divisible by `seconds`

  This function is used to bucket all datetimes in a given interval to a single
  datetime, usable in cache key construction
  """
  def round_datetime(datetime, opts \\ []) do
    case Keyword.get(opts, :second, 300) do
      0 ->
        datetime

      seconds ->
        rounding = Keyword.get(opts, :rounding, :down)
        datetime_unix = DateTime.to_unix(datetime)

        datetime_unix =
          case rounding do
            :up -> datetime_unix + seconds
            :down -> datetime_unix
          end

        datetime_unix
        |> div(seconds)
        |> Kernel.*(seconds)
        |> DateTime.from_unix!()
    end
  end

  # Private
  defp maybe_pluralize_interval(str, 1), do: str
  defp maybe_pluralize_interval(str, _), do: str <> "s"
end
