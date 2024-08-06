defmodule Sanbase.SmartContracts.SanbaseNFT do
  import Sanbase.SmartContracts.Utils,
    only: [call_contract: 4, call_contract_batch: 5, format_address: 1]

  require Logger

  @contract_mainnet "0x211E14C8cc67F9EF05cC84F80Dc036Ff2F548949"

  @json_file "sanbase_nft_abi.json"
  @external_resource json_file = Path.join(__DIR__, @json_file)
  @abi File.read!(json_file) |> Jason.decode!()

  # test address with subscriptions: 0x89c276d6e0fda36d7796af0d27a08176cc0f1976
  def abi(), do: @abi

  def contract(), do: @contract_mainnet

  def nft_subscriptions_data(address) do
    tokens_count = balance_of(address)

    if tokens_count > 0 do
      token_ids =
        0..(tokens_count - 1)
        |> Enum.map(fn idx ->
          address = format_address(address)
          execute("tokenOfOwnerByIndex", [address, idx]) |> List.first()
        end)

      valid_token_ids =
        Enum.filter(token_ids, fn token_id -> execute("isValid", [token_id]) |> hd() end)

      non_valid_token_ids = token_ids -- valid_token_ids
      %{valid: valid_token_ids, non_valid: non_valid_token_ids}
    else
      %{valid: [], non_valid: []}
    end
  end

  def balances_of(addresses) do
    addresses_args = Enum.map(addresses, &format_address/1) |> Enum.map(&List.wrap/1)

    execute_batch("balanceOf", addresses_args)
    |> Enum.map(fn
      [balance] -> balance
      _ -> 0
    end)
  end

  def balance_of(address) do
    address = format_address(address)

    execute("balanceOf", [address])
    |> case do
      [balance] -> balance
      _ -> 0
    end
  end

  def function_abi(function) do
    abi()
    |> ABI.parse_specification()
    |> Enum.filter(&(&1.function == function))
    |> hd()
  end

  def execute(function_name, args) do
    call_contract(
      contract(),
      function_abi(function_name),
      args,
      function_abi(function_name).returns
    )
  end

  def execute_batch(function_name, args) do
    call_contract_batch(
      contract(),
      function_abi(function_name),
      args,
      function_abi(function_name).returns,
      transform_args_list_fun: fn list -> list ++ ["latest"] end
    )
  end
end
