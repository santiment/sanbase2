defmodule Sanbase.Signal.Validation.Target do
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

  def valid_eth_wallet_target?(%{watchlist_id: _}) do
    {:error, "Watchlists are not valid ethereum wallet target"}
  end

  def valid_eth_wallet_target?(target), do: valid_target?(target)
end
