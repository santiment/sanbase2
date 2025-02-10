defmodule Sanbase.MarkExchanges do
  @moduledoc false
  import Sanbase.MapUtils, only: [replace_lazy: 3]

  @exchange_labels ["centralized_exchange", "decentralized_exchange", "CEX", "DEX"]

  @doc ~s"""
  Get a list of maps where one of the keys is :address, :from_address or :to_address
  and another element is :labels.
  Add is_exchange: true to the address map if any of the labels
  is an exchange, add is_exhange: false otherwise.

    ## Example
    iex> Sanbase.MarkExchanges.mark_exchanges([%{address: %{address: "0x123}, labels: [%{name: "centralized_exchange"}]}])
  """
  def mark_exchanges([]), do: {:ok, []}

  def mark_exchanges(list) do
    add_is_exchange = fn address_map ->
      labels = List.wrap(address_map[:labels] || address_map[:label] || [])
      is_exchange = Enum.any?(labels, &(&1[:name] in @exchange_labels))
      Map.put(address_map, :is_exchange, is_exchange)
    end

    result =
      Enum.map(list, fn elem ->
        elem
        |> replace_lazy(:address, fn -> add_is_exchange.(elem.address) end)
        |> replace_lazy(:from_address, fn -> add_is_exchange.(elem.from_address) end)
        |> replace_lazy(:to_address, fn -> add_is_exchange.(elem.to_address) end)
      end)

    {:ok, result}
  end
end
