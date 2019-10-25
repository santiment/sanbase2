defmodule Sanbase.Validation do
  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]
  defguard is_valid_price(price) when is_number(price) and price >= 0
  defguard is_valid_percent(percent) when is_number(percent) and percent >= -100
  defguard is_valid_percent_change(percent) when is_number(percent) and percent > 0

  defguard is_valid_min_max_price(min, max)
           when min < max and is_valid_price(min) and is_valid_price(max)

  def valid_percent?(percent) when is_valid_percent(percent), do: :ok

  def valid_percent?(percent),
    do: {:error, "#{inspect(percent)} is not a valid percent"}

  def valid_time_window?(time_window) when is_binary(time_window) do
    Regex.match?(~r/^\d+[smhdw]$/, time_window)
    |> case do
      true -> :ok
      false -> {:error, "#{inspect(time_window)} is not a valid time window"}
    end
  end

  def valid_time_window?(time_window),
    do: {:error, "#{inspect(time_window)} is not a valid time window"}

  def time_window_is_whole_days?(time_window) do
    case rem(str_to_sec(time_window), 86_400) do
      0 ->
        :ok

      _ ->
        {:error, "Time window should represent whole days. Time window provided: #{time_window}"}
    end
  end

  def time_window_bigger_than?(time_window, min_time_window) do
    case str_to_sec(time_window) >= str_to_sec(min_time_window) do
      true ->
        :ok

      false ->
        {:error,
         "Time window should be bigger than #{min_time_window}. Time window provided: #{
           time_window
         }"}
    end
  end

  def valid_iso8601_datetime_string?(time) when is_binary(time) do
    case Time.from_iso8601(time) do
      {:ok, _time} ->
        :ok

      _ ->
        {:error, "#{time} isn't a valid ISO8601 time"}
    end
  end

  def valid_iso8601_datetime_string?(_), do: {:error, "Not valid ISO8601 time"}

  def valid_url?(url) do
    case URI.parse(url) do
      %URI{scheme: nil} -> {:error, "`#{url}` is missing scheme"}
      %URI{host: nil} -> {:error, "`#{url}` is missing host"}
      %URI{path: nil} -> {:error, "`#{url}` is missing path"}
      _ -> :ok
    end
  end

  def valid_threshold?(t) when is_number(t) and t > 0, do: :ok

  def valid_threshold?(t) do
    {:error, "#{inspect(t)} is not valid threshold. It must be a number bigger than 0"}
  end

  def valid_metric?(metric) do
    case metric in Sanbase.Metric.available_metrics() do
      true ->
        :ok

      false ->
        {:error, "#{inspect(metric)} is not a valid metric."}
    end
  end
end
