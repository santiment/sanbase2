defmodule Sanbase.Alert.Validation.Target do
  @doc ~s"""
  Check if a given `target` is a valid target argument for an alert.

  A target can be valid if it match one of many criteria. For more information,
  check the function headers.
  """
  def valid_target?("default"), do: :ok

  def valid_target?(%{user_list: int}) when is_integer(int), do: :ok
  def valid_target?(%{watchlist_id: int}) when is_integer(int), do: :ok
  def valid_target?(%{text: text}) when is_binary(text), do: :ok
  def valid_target?(%{word: word}) when is_binary(word), do: :ok

  def valid_target?(%{market_segments: [market_segment | _]}) when is_binary(market_segment),
    do: :ok

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

  @doc ~s"""
  Check if a target is a valid eth_wallet alert target.

  It is a valid target if:
    - It is %{eth_address: addres_or_addresses}
    - It is not a watchlist
    - It returns true for valid_target
  """
  @spec valid_eth_wallet_target?(any) :: :ok | {:error, <<_::64, _::_*8>>}
  def valid_eth_wallet_target?(%{eth_address: address_or_addresses}) do
    valid_crypto_address?(address_or_addresses)
  end

  def valid_eth_wallet_target?(%{word: _}) do
    {:error, "Word is not valid wallet target"}
  end

  def valid_eth_wallet_target?(%{text: _}) do
    {:error, "Text is not valid wallet target"}
  end

  def valid_eth_wallet_target?(%{user_list: _}) do
    {:error, "Watchlists are not valid wallet target"}
  end

  def valid_eth_wallet_target?(%{watchlist_id: _}) do
    {:error, "Watchlists are not valid wallet target"}
  end

  def valid_eth_wallet_target?(target), do: valid_target?(target)

  @doc ~s"""
  Check if the target is a valid crypto address.

  A valid crypto address is:
    - An address or lsit of addresses
    - A `slug`. In this case the blockchain addresses associated with this
      slug will be used.
  """
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
    case Sanbase.Clickhouse.HistoricalBalance.selector_to_args(selector) do
      %{module: _, blockchain: _, asset: _, decimals: _, slug: _} -> :ok
      {:error, _error} -> "#{inspect(selector)} is not a valid  historical balance selector."
    end
  end

  def valid_historical_balance_selector?(selector) do
    {:error,
     "#{inspect(selector)} is not a valid historical balance selector - it has to be a map"}
  end

  def valid_infrastructure_selector?(%{infrastructure: infrastructure})
      when is_binary(infrastructure) do
    supported_infrastructures = Sanbase.Clickhouse.HistoricalBalance.supported_infrastructures()

    case infrastructure in supported_infrastructures do
      true ->
        :ok

      false ->
        {:error,
         "Infrastructure #{infrastructure} is not in the list of supported infrastructures: #{inspect(supported_infrastructures)}"}
    end
  end

  def valid_infrastructure_selector?(_) do
    {:error,
     "The provided selector is not a valid infrastructure selector. The selector must be a map with a single key 'infrastructure'"}
  end
end
