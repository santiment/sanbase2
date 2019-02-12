defmodule Sanbase.Signals.Validation do
  @notification_channels ["telegram", "email"]

  def valid_notification_channels(), do: @notification_channels

  def valid_percent?(percent) when is_number(percent) and percent >= -100, do: true
  def valid_percent?(_), do: false

  def valid_price?(price) when is_number(price) and price >= 0, do: :ok
  def valid_price?(_), do: :error

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

  def valid_target?(target) when is_binary(target), do: :ok
  def valid_target?({:user_list, int}) when is_integer(int), do: :ok

  def valid_target?(list) when is_list(list) do
    Enum.find(list, fn elem -> not is_binary(elem) end)
    |> case do
      nil -> :ok
      _ -> {:error, "The target list contains elements that are not string"}
    end
  end

  def valid_target?(_), do: :error
end
