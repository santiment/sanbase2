defmodule Sanbase.Validation do
  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]
  defguard is_valid_price(price) when is_number(price) and price >= 0
  defguard is_valid_percent(percent) when is_number(percent) and percent >= -100
  defguard is_valid_percent_change(percent) when is_number(percent) and percent > 0

  defguard is_valid_min_max(min, max)
           when min < max and is_number(min) and is_number(max)

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
         "Time window should be bigger than #{min_time_window}. Time window provided: #{time_window}"}
    end
  end

  def valid_iso8601_time_string?(time) when is_binary(time) do
    case Time.from_iso8601(time) do
      {:ok, _time} ->
        :ok

      _ ->
        {:error, "#{time} is not a valid ISO8601 time"}
    end
  end

  def valid_iso8601_time_string?(str), do: {:error, "#{inspect(str)} is not a valid ISO8601 time"}

  def valid_threshold?(t) when is_number(t) and t > 0, do: :ok

  def valid_threshold?(t) do
    {:error, "#{inspect(t)} is not valid threshold. It must be a number bigger than 0"}
  end

  def valid_metric?(metric) do
    Sanbase.Metric.has_metric?(metric)
  end

  def valid_signal?(signal) do
    Sanbase.Signal.has_signal?(signal)
  end

  def valid_5m_min_interval_metric?(metric) do
    with {:ok, %{min_interval: min_interval}} <- Sanbase.Metric.metadata(metric),
         interval_sec when is_number(interval_sec) and interval_sec <= 300 <-
           Sanbase.DateTimeUtils.str_to_sec(min_interval) do
      :ok
    else
      _ ->
        {:error,
         "The metric #{inspect(metric)} is not supported, is deprecated or is mistyped or does not have min interval equal or less than to 5 minutes."}
    end
  end

  def valid_above_5m_min_interval_metric?(metric) do
    with {:ok, %{min_interval: min_interval}} <- Sanbase.Metric.metadata(metric),
         interval_sec when is_number(interval_sec) and interval_sec > 300 <-
           Sanbase.DateTimeUtils.str_to_sec(min_interval) do
      :ok
    else
      _ ->
        {:error,
         "The metric #{inspect(metric)} is not supported, is deprecated or is mistyped or does not have min interval equal or bigger than to 1 day."}
    end
  end

  def valid_url?(url, opts \\ []) do
    check_host_online? = Keyword.get(opts, :check_host_online, false)
    uri = URI.parse(url)

    cond do
      url == "" ->
        {:error, "URL is an empty string"}

      uri.scheme == nil ->
        {:error, "URL '#{url}' is missing a scheme (e.g. https)"}

      uri.host == nil ->
        {:error, "URL '#{url}' is missing a host"}

      uri.path == nil ->
        {:error, "URL '#{url}' is missing path (e.g. missing the /image.png part)"}

      # If true this will try to DNS resolve the hostname and check if it exists
      check_host_online? == true ->
        case :inet.gethostbyname(to_charlist(uri.host)) do
          {:ok, _} -> :ok
          {:error, _} -> {:error, "URL '#{url}' host is not resolvable"}
        end

      true ->
        :ok
    end
  end
end
