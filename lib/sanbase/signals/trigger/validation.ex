defmodule Sanbase.Signals.Validation do
  @notification_channels ["telegram", "email"]

  defguard is_valid_price(price) when is_number(price) and price >= 0
  defguard is_valid_percent(percent) when is_number(percent) and percent >= -100
  defguard is_valid_percent_change(percent) when is_number(percent) and percent > 0

  defguard is_valid_min_max_price(min, max)
           when min < max and is_valid_price(min) and is_valid_price(max)

  def valid_notification_channels(), do: @notification_channels

  def valid_notification_channel(channel) when channel in @notification_channels, do: :ok

  def valid_notification_channel(channel),
    do: {:error, "#{inspect(channel)} is not a valid notification channel"}

  def valid_percent?(percent) when is_valid_percent(percent), do: :ok

  def valid_percent?(percent),
    do: {:error, "#{inspect(percent)} is not a valid percent"}

  def valid_percent_change_operation?(%{percent_up: percent})
      when is_valid_percent_change(percent) do
    :ok
  end

  def valid_percent_change_operation?(%{percent_down: percent})
      when is_valid_percent_change(percent) do
    :ok
  end

  def valid_percent_change_operation?(operation),
    do: {:error, "#{inspect(operation)} is not a valid percent change operation"}

  def valid_absolute_value_operation?(%{above: above}) when is_valid_price(above), do: :ok
  def valid_absolute_value_operation?(%{below: below}) when is_valid_price(below), do: :ok

  def valid_absolute_value_operation?(%{inside_channel: [min, max]} = operation),
    do: do_valid_absolute_value_operation?(operation, [min, max])

  def valid_absolute_value_operation?(%{outside_channel: [min, max]} = operation),
    do: do_valid_absolute_value_operation?(operation, [min, max])

  def valid_absolute_value_operation?(operation),
    do: {:error, "#{inspect(operation)} is not a valid absolute value operation"}

  def valid_absolute_change_operation?(%{amount_up: value}) when is_number(value), do: :ok
  def valid_absolute_change_operation?(%{amount_down: value}) when is_number(value), do: :ok
  def valid_absolute_change_operation?(%{amount: value}) when is_number(value), do: :ok

  def valid_absolute_change_operation?(operation),
    do: {:error, "#{inspect(operation)} is not a valid absolute change operation"}

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

  def valid_target?(%{user_list: int}) when is_integer(int), do: :ok
  def valid_target?(%{slug: slug}) when is_binary(slug), do: :ok

  def valid_target?(%{slug: slugs}) when is_list(slugs) do
    Enum.find(slugs, fn slug -> not is_binary(slug) end)
    |> case do
      nil -> :ok
      _ -> {:error, "The target list contains elements that are not string"}
    end
  end

  def valid_target?(target),
    do: {:error, "#{inspect(target)} is not a valid target"}

  def valid_eth_wallet_target?(%{eth_address: address})
      when is_binary(address) or is_list(address) do
    address
    |> List.wrap()
    |> Enum.find(fn elem -> not is_binary(elem) end)
    |> case do
      nil -> :ok
      _ -> {:error, "The target list of ethereum addresses contains elements that are not string"}
    end
  end

  def valid_eth_wallet_target?(%{user_list: _}) do
    {:error, "Watchlists are not valid ethereum wallet target"}
  end

  def valid_eth_wallet_target?(target), do: valid_target?(target)

  def valid_slug?(%{slug: slug}) when is_binary(slug), do: :ok

  def valid_slug?(slug) do
    {:error,
     "#{inspect(slug)} is not a valid slug. A valid slug is a map with a single slug key and string value"}
  end

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

  # private functions
  defp do_valid_absolute_value_operation?(_, [min, max]) when is_valid_min_max_price(min, max),
    do: :ok

  defp do_valid_absolute_value_operation?(operation, _),
    do: {:error, "#{inspect(operation)} is not a valid absolute value operation"}
end
