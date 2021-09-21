defmodule Sanbase.Utils.BlockchainAddressUtils do
  @doc ~s"""
  Get a list where every element has a key-value pair where the key is `address`,
  `from_address` or `to_address` and the value is a string and transform that
  string to a map with `address` as a key and the string value as its value.
  Additionally, the provided `infrastructure` is added as a key to every map

    ## Example
    iex> Sanbase.Utils.BlockchainAddressUtils.transform_address_to_map([%{address: "0x123"}, %{address: "0x1234"}], "ETH")
    [%{address: %{address: "0x123", infrastructure: "ETH"}}, %{address: %{address: "0x1234", infrastructure: "ETH"}}]

    iex> Sanbase.Utils.BlockchainAddressUtils.transform_address_to_map([%{from_address: "0x123"}, %{from_address: "0x1234"}], "ETH")
    [%{from_address: %{address: "0x123", infrastructure: "ETH"}}, %{from_address: %{address: "0x1234", infrastructure: "ETH"}}]


    iex> Sanbase.Utils.BlockchainAddressUtils.transform_address_to_map([%{to_address: "0x123"}, %{to_address: "0x1234"}], "ETH")
    [%{to_address: %{address: "0x123", infrastructure: "ETH"}}, %{to_address: %{address: "0x1234", infrastructure: "ETH"}}]
  """
  def transform_address_to_map(list, infrastructure \\ nil) do
    address_to_map =
      case infrastructure do
        nil -> fn address -> %{address: address} end
        _ -> fn address -> %{address: address, infrastructure: infrastructure} end
      end

    result =
      list
      |> Enum.map(fn map ->
        map
        |> Map.replace(:address, address_to_map.(map[:address]))
        |> Map.replace(:from_address, address_to_map.(map[:from_address]))
        |> Map.replace(:to_address, address_to_map.(map[:to_address]))
      end)

    {:ok, result}
  end
end
