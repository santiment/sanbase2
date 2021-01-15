defmodule Sanbase.SmartContracts.UniswapPair do
  import Sanbase.SmartContracts.Utils, only: [format_address: 1, format_number: 2]

  @type address :: String.t()

  @bac_san_pair_contract "0x0D88ba937A8492AE235519334Da954EbA73625dF"
  @san_eth_pair_contract "0x430ba84fadf427ee5e8d4d78538b64c1e7456020"
  @all_pair_contracts [@bac_san_pair_contract, @san_eth_pair_contract]
  @decimals 18

  def bac_san_pair_contract, do: @bac_san_pair_contract
  def san_eth_pair_contract, do: @san_eth_pair_contract
  def all_pair_contracts, do: @all_pair_contracts

  @spec decimals(address) :: non_neg_integer()
  def decimals(contract) do
    [decimals] = call_contract(contract, "decimals()", [], [{:uint, 8}])
    decimals
  end

  @spec token0(address) :: address
  def token0(contract) do
    [address] = call_contract(contract, "token0()", [], [:address])
    "0x" <> Base.encode16(address, case: :lower)
  end

  @spec token1(address) :: address
  def token1(contract) do
    [address] = call_contract(contract, "token1()", [], [:address])
    "0x" <> Base.encode16(address, case: :lower)
  end

  @spec reserves(address) :: {float(), float()}
  def reserves(contract) do
    [token0_reserves, token1_reserves, _] =
      call_contract(
        contract,
        "getReserves()",
        [],
        [{:uint, 112}, {:uint, 112}, {:uint, 32}]
      )

    {format_number(token0_reserves, @decimals), format_number(token1_reserves, @decimals)}
  end

  @spec total_supply(address) :: float()
  def total_supply(contract) do
    [total_supply] = call_contract(contract, "totalSupply()", [], [{:uint, 256}])
    format_number(total_supply, @decimals)
  end

  @spec balance_of(address, address) :: float()
  def balance_of(address, contract) do
    address = format_address(address)
    [balance] = call_contract(contract, "balanceOf(address)", [address], [{:uint, 256}])
    format_number(balance, @decimals)
  end

  @spec get_san_position(address) :: 0 | 1
  def get_san_position(contract) do
    cond do
      token0(contract) == Sanbase.SantimentContract.contract() ->
        0

      token1(contract) == Sanbase.SantimentContract.contract() ->
        1
    end
  end

  @spec call_contract(address, String.t(), list(), list()) :: any()
  def call_contract(contract, call, args, return_types) do
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
