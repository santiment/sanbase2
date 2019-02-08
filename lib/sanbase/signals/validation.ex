defmodule Sanbase.Signals.Validation do
  @notification_channels ["telegram", "email"]

  def valid_notification_channels(), do: @notification_channels

  def valid_percent?(percent) when is_float(percent), do: percent > 0
  def valid_percent?(_), do: false

  def valid_time_window?(time_window) when is_binary(time_window) do
    Regex.match?(~r/^\d+[mhdw]$/, time_window)
  end

  def valid_time_window?(_), do: false
end
