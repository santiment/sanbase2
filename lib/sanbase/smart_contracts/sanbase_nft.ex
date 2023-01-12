defmodule Sanbase.SmartContracts.SanbaseNft do
  import Sanbase.SmartContracts.Utils,
    only: [call_contract: 4, format_address: 1]

  require Logger

  alias Sanbase.Utils.Config

  @contract "0x7f985e8ad29438907a2cc8ff3d526d9a1693442c"
  @json_file "sanbase_nft_abi.json"
  @external_resource json_file = Path.join(__DIR__, @json_file)
  @abi File.read!(json_file) |> Jason.decode!()

  # test address with subscriptions: 0x89c276d6e0fda36d7796af0d27a08176cc0f1976
  def abi(), do: @abi

  def has_valid_nft_subscription?(address) do
    now_unix = Timex.now() |> DateTime.to_unix()
    tokens_count = balance_of(address)

    if tokens_count > 0 do
      0..(tokens_count - 1)
      |> Enum.map(fn idx ->
        address = format_address(address)
        execute("tokenOfOwnerByIndex", [address, idx]) |> List.first()
      end)
      |> Enum.filter(fn token_id ->
        execute("isValid", [token_id])
      end)
      |> Enum.map(fn token_id ->
        execute("getExpiration", [token_id]) |> List.first()
      end)
      |> Enum.any?(fn exp_unix -> exp_unix > now_unix end)
    else
      false
    end
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
    contract_call = fn ->
      call_contract(
        @contract,
        function_abi(function_name),
        args,
        function_abi(function_name).returns
      )
    end

    maybe_replace_goerly(contract_call)
  end

  defp maybe_replace_goerly(func) do
    maybe_put_goerly_url()

    try do
      func.()
    rescue
      e ->
        Logger.error("Error occurred while executing smart contract call: #{inspect(e)}")
        {:error, "Error occurred while executing smart contract call."}
    after
      maybe_put_eth_mainnet_url()
    end
  end

  defp maybe_put_goerly_url() do
    if is_dev_or_stage?() do
      Application.put_env(:ethereumex, :url, System.get_env("GOERLY_URL"))
    end
  end

  defp maybe_put_eth_mainnet_url() do
    if is_dev_or_stage?() do
      Application.put_env(:ethereumex, :url, System.get_env("PARITY_URL"))
    end
  end

  defp is_dev_or_stage?() do
    Config.module_get(Sanbase, :deployment_env) in ["dev", "stage"]
  end
end
