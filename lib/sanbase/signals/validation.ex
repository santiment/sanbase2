defmodule Sanbase.Signals.Validation do
  @notification_channels ["telegram", "email"]

  def valid_notification_channels(), do: @notification_channels

  def valid_percent?(percent) when is_float(percent), do: true
  def valid_percent?(_), do: false

  def valid_time_window?(time_window) when is_binary(time_window) do
    Regex.match?(~r/^\d+[smhdw]$/, time_window)
  end

  def valid_time_window?(_), do: false

  def valid_iso8601_datetime_string?(time) when is_binary(time) do
    case Time.from_iso8601(time) do
      {:ok, _time} ->
        :ok

      _ ->
        {:error, "#{time} isn't a valid ISO8601 time"}
    end
  end

  def valid_iso8601_datetime_string?(_), do: :error
end
