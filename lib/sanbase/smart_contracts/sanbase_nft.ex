defmodule Sanbase.SmartContracts.SanbaseNftInterface do
  def nft_subscriptions(user) do
    user = Sanbase.Repo.preload(user, :eth_accounts)

    nft_data =
      user.eth_accounts
      |> Enum.map(fn ea ->
        address = String.downcase(ea.address)

        %{
          address: address,
          token_ids: Sanbase.SmartContracts.SanbaseNft.nft_subscriptions_data(address)
        }
      end)

    %{
      nft_data: nft_data,
      has_valid_nft: has_valid_nft?(nft_data),
      nft_count: nft_count(nft_data)
    }
  end

  defp has_valid_nft?(data) do
    data
    |> Enum.filter(fn %{token_ids: token_ids} -> length(token_ids) > 0 end)
    |> Enum.any?()
  end

  defp nft_count(data) do
    data
    |> Enum.reduce(0, fn %{token_ids: token_ids}, acc -> acc + length(token_ids) end)
  end
end

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

  def nft_subscriptions_data(address) do
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
      |> Enum.filter(fn token_id ->
        exp_unix = execute("getExpiration", [token_id]) |> List.first()

        if exp_unix != nil and exp_unix > now_unix do
          true
        else
          false
        end
      end)
    else
      []
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
