defmodule Sanbase.Signals.Validation do
  @notification_channels ["telegram", "email"]

  def valid_notification_channels(), do: @notification_channels

  def valid_notification_channel(channel) when channel in @notification_channels, do: :ok

  def valid_notification_channel(channel),
    do: {:error, "#{inspect(channel)} is not a valid notification channel"}

  def valid_percent?(percent) when is_number(percent) and percent >= -100, do: true

  def valid_percent?(percent),
    do: {:error, "#{inspect(percent)} is not a valid percent"}

  @spec valid_price?(any()) :: :ok | {:error, <<_::64, _::_*8>>}
  def valid_price?(price) when is_number(price) and price >= 0, do: :ok
  def valid_price?(price), do: {:error, "#{inspect(price)} is not a valid price"}

  def valid_time_window?(time_window) when is_binary(time_window) do
    Regex.match?(~r/^\d+[smhdw]$/, time_window)
    |> case do
      true -> :ok
      false -> {:error, "#{inspect(time_window)} is not a valid time window"}
    end
  end

  def valid_time_window?(time_window),
    do: {:error, "#{inspect(time_window)} is not a valid time window"}

  def valid_iso8601_datetime_string?(time) when is_binary(time) do
    case Time.from_iso8601(time) do
      {:ok, _time} ->
        :ok

      _ ->
        {:error, "#{time} isn't a valid ISO8601 time"}
    end
  end

  def valid_iso8601_datetime_string?(_), do: {:error, "Not valid ISO8601 time"}

  def valid_target?(target) when is_binary(target), do: :ok
  def valid_target?(%{user_list: int}) when is_integer(int), do: :ok

  def valid_target?(list) when is_list(list) do
    Enum.find(list, fn elem -> not is_binary(elem) end)
    |> case do
      nil -> :ok
      _ -> {:error, "The target list contains elements that are not string"}
    end
  end

  def valid_target?(target),
    do: {:error, "#{inspect(target)} is not a valid target"}

  def valid_url?(url) do
    case URI.parse(url) do
      %URI{scheme: nil} -> {:error, "`#{url}` is missing scheme"}
      %URI{host: nil} -> {:error, "`#{url}` is missing host"}
      %URI{path: nil} -> {:error, "`#{url}` is missing path"}
      _ -> :ok
    end
  end
end
