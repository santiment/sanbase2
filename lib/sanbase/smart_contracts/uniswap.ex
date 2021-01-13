defmodule Sanbase.SmartContracts.Uniswap do
  def staked_san(address, contract, opts) do
    san_position = Keyword.fetch!(opts, :san_position_in_pair)

    total_san_staked = Enum.at(reserves(contract), san_position) / Sanbase.Math.ipow(10, 18)
    address_staked_tokens = balance_of(address, contract)
    total_staked_tokens = total_supply(contract)

    if total_staked_tokens > 0 do
      part_of_all_for_address = address_staked_tokens / total_staked_tokens
      part_of_all_for_address * total_san_staked
    else
      0
    end
  end

  def reserves(contract) do
    call_contract(
      contract,
      "getReserves()",
      [],
      [{:uint, 112}, {:uint, 112}, {:uint, 32}]
    )
  end

  def total_supply(contract) do
    [total_supply] = call_contract(contract, "totalSupply()", [], [{:uint, 256}])
    total_supply / Sanbase.Math.ipow(10, 18)
  end

  def balance_of(address, contract) do
    address = format_address(address)
    [balance] = call_contract(contract, "balanceOf(address)", [address], [{:uint, 256}])
    balance / Sanbase.Math.ipow(10, 18)
  end

  # helpers

  defp format_address(address) do
    {:ok, address} =
      address
      |> String.slice(2..-1)
      |> Base.decode16(case: :mixed)

    address
  end

  defp call_contract(contract, call, args, return_types) do
    abi = ABI.encode(call, args) |> Base.encode16(case: :lower)

    {:ok, res_enc} =
      Ethereumex.HttpClient.eth_call(%{
        data: "0x" <> abi,
        to: contract
      })

    res_enc
    |> String.slice(2..-1)
    |> Base.decode16!(case: :lower)
    |> ABI.TypeDecoder.decode_raw(return_types)
  end
end
