defmodule Sanbase.SmartContracts.UniswapPair do
  import Sanbase.SmartContracts.Utils,
    only: [call_contract: 4, call_contract_batch: 5, format_address: 1, format_number: 2]

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

    call_contract(contract, "balanceOf(address)", [address], [{:uint, 256}])
    |> case do
      [balance] -> format_number(balance, @decimals)
      {:error, _} -> +0.0
    end
  end

  def balances_of(addresses, contract) do
    addresses_args = Enum.map(addresses, &format_address/1) |> Enum.map(&List.wrap/1)
    # balanceOf has 2 optional parameters - block number and opts. In case of
    # batching, the batch_request/1 function automatically appends `batch: true`
    # to the arguments list. If the first optional param is not explicilty set
    # to "latest", then it is populated by a keyword list and fails.
    opts = [transform_args_list_fun: fn list -> list ++ ["latest"] end]

    call_contract_batch(contract, "balanceOf(address)", addresses_args, [{:uint, 256}], opts)
    |> Enum.map(fn [balance] -> [format_number(balance, @decimals)] end)
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
end
