defmodule Sanbase.Signal.Validation.Target do
  def valid_target?("default"), do: :ok

  def valid_target?(%{user_list: int}) when is_integer(int), do: :ok
  def valid_target?(%{watchlist_id: int}) when is_integer(int), do: :ok

  def valid_target?(%{text: text}) when is_binary(text), do: :ok

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

  def valid_eth_wallet_target?(%{eth_address: address_or_addresses}) do
    valid_crypto_address?(address_or_addresses)
  end

  def valid_eth_wallet_target?(%{user_list: _}) do
    {:error, "Watchlists are not valid ethereum wallet target"}
  end

  def valid_eth_wallet_target?(%{watchlist_id: _}) do
    {:error, "Watchlists are not valid ethereum wallet target"}
  end

  def valid_eth_wallet_target?(target), do: valid_target?(target)

  def valid_crypto_address?(%{slug: slug}), do: valid_target?(%{slug: slug})

  def valid_crypto_address?(%{address: address_or_addresses}) do
    valid_crypto_address?(address_or_addresses)
  end

  def valid_crypto_address?(address_or_addresses)
      when is_binary(address_or_addresses) or is_list(address_or_addresses) do
    address_or_addresses
    |> List.wrap()
    |> Enum.find(fn elem -> not is_binary(elem) end)
    |> case do
      nil ->
        :ok

      _ ->
        {:error,
         "#{inspect(address_or_addresses)} is not a valid crypto address. The list contains elements that are not string"}
    end
  end

  def valid_crypto_address?(data), do: {:error, "#{inspect(data)} is not a valid crypto address"}

  def valid_historical_balance_selector?(selector) when is_map(selector) do
    keys = Map.keys(selector)

    case Enum.all?(keys, fn key -> key in [:infrastructure, :currency, :slug] end) do
      true -> :ok
      false -> {:error, "#{inspect(selector)} is not a valid selector - it has unsupported keys"}
    end
  end

  def valid_historical_balance_selector?(selector) do
    {:error, "#{inspect(selector)} is not a valid selector - it has to be a map"}
  end
end
