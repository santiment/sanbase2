defmodule Sanbase.Signal.Validation do
  import Sanbase.Validation

  @notification_channels ["telegram", "email"]

  def valid_notification_channels(), do: @notification_channels

  def valid_notification_channel?(channel) when channel in @notification_channels, do: :ok

  def valid_notification_channel?(channel),
    do: {:error, "#{inspect(channel)} is not a valid notification channel"}

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

  def valid_target?("default"), do: :ok

  def valid_target?(%{user_list: int}) when is_integer(int), do: :ok
  def valid_target?(%{watchlist_id: int}) when is_integer(int), do: :ok
  def valid_target?(%{word: word}) when is_binary(word), do: :ok

  def valid_target?(%{word: words}) when is_list(words) do
    Enum.find(words, fn word -> not is_binary(word) end)
    |> case do
      nil -> :ok
      _ -> {:error, "The target list contains elements that are not string"}
    end
  end

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

  def valid_daily_active_addresses_operation?(op) do
    has_valid_operation? = [
      valid_percent_change_operation?(op),
      valid_absolute_value_operation?(op)
    ]

    if Enum.member?(has_valid_operation?, :ok) do
      :ok
    else
      {:error, "#{inspect(op)} is not valid absolute change or percent change operation."}
    end
  end

  # private functions
  defp do_valid_absolute_value_operation?(_, [min, max]) when is_valid_min_max_price(min, max),
    do: :ok

  defp do_valid_absolute_value_operation?(operation, _),
    do: {:error, "#{inspect(operation)} is not a valid absolute value operation"}
end
