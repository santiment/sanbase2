defmodule Sanbase.SmartContracts.UniswapPair do
  import Sanbase.SmartContracts.Utils,
    only: [call_contract: 4, call_contract_batch: 5, format_address: 1, format_number: 2]

  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2]

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

  @spec token0(address) :: address | {:error, any()}
  def token0(contract) do
    call_contract(contract, "token0()", [], [:address])
    |> case do
      [address] -> "0x" <> Base.encode16(address, case: :lower)
      {:error, _} = error -> error
    end
  end

  @spec token1(address) :: address | {:error, any()}
  def token1(contract) do
    call_contract(contract, "token1()", [], [:address])
    |> case do
      [address] -> "0x" <> Base.encode16(address, case: :lower)
      {:error, _} = error -> error
    end
  end

  @spec reserves(address) :: {float(), float()} | {:error, any()}
  def reserves(contract) do
    call_contract(
      contract,
      "getReserves()",
      [],
      [{:uint, 112}, {:uint, 112}, {:uint, 32}]
    )
    |> case do
      [token0_reserves, token1_reserves, _] ->
        {format_number(token0_reserves, @decimals), format_number(token1_reserves, @decimals)}

      {:error, _} = error ->
        error
    end
  end

  @spec total_supply(address) :: float() | {:error, any()}
  def total_supply(contract) do
    call_contract(contract, "totalSupply()", [], [{:uint, 256}])
    |> case do
      [total_supply] -> format_number(total_supply, @decimals)
      {:error, _} = error -> error
    end
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

  @doc ~s"""
  Fetch the balances of a list of addresses for the given pair contract
  in a single batched RPC call.

  Returns the balances in the same order as the given addresses. A single
  failed request in the batch fails the whole call, as the result would no
  longer correspond 1:1 to the addresses list.

  ## Examples

      iex> UniswapPair.balances_of([addr1, addr2], contract)
      {:ok, [1.0, 2.5]}

      iex> UniswapPair.balances_of([addr1, addr2], contract)
      {:error, %Mint.TransportError{reason: :nxdomain}}
  """
  @spec balances_of([address], address) :: {:ok, [float()]} | {:error, any()}
  def balances_of(addresses, contract) do
    addresses_args = Enum.map(addresses, &format_address/1) |> Enum.map(&List.wrap/1)
    # balanceOf has 2 optional parameters - block number and opts. In case of
    # batching, the batch_request/1 function automatically appends `batch: true`
    # to the arguments list. If the first optional param is not explicilty set
    # to "latest", then it is populated by a keyword list and fails.
    opts = [transform_args_list_fun: fn list -> list ++ ["latest"] end]

    with results when is_list(results) <-
           call_contract_batch(
             contract,
             "balanceOf(address)",
             addresses_args,
             [{:uint, 256}],
             opts
           ) do
      Enum.reduce_while(results, {:ok, []}, fn
        [balance], {:ok, acc} -> {:cont, {:ok, [format_number(balance, @decimals) | acc]}}
        {:error, _} = error, _acc -> {:halt, error}
      end)
      |> maybe_apply_function(&Enum.reverse/1)
    end
  end

  @spec get_san_position(address) :: 0 | 1 | {:error, any()}
  def get_san_position(contract) do
    san_contract = Sanbase.SantimentContract.contract()
    token0 = token0(contract)
    token1 = token1(contract)

    cond do
      token0 == san_contract ->
        0

      token1 == san_contract ->
        1

      # Propagate the underlying RPC/transport error so callers and logs can
      # distinguish a failed contract call from "SAN is not part of this pair".
      match?({:error, _}, token0) ->
        token0

      match?({:error, _}, token1) ->
        token1

      true ->
        {:error, :san_position_not_found}
    end
  end
end
