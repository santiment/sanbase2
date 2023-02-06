defmodule Sanbase.SmartContracts.SanbaseNFTInterface do
  alias Sanbase.Accounts.User

  def nft_subscriptions(%User{} = user) do
    user = Sanbase.Repo.preload(user, :eth_accounts)

    nft_data =
      user.eth_accounts
      |> Enum.map(fn ea ->
        address = String.downcase(ea.address)
        data = Sanbase.SmartContracts.SanbaseNFT.nft_subscriptions_data(address)

        %{
          address: address,
          token_ids: data.valid,
          non_valid_token_ids: data.non_valid
        }
      end)

    %{
      nft_data: nft_data,
      has_valid_nft: has_valid_nft?(nft_data),
      has_non_valid_nft: has_non_valid_nft?(nft_data),
      nft_count: nft_count(nft_data),
      non_valid_nft_count: non_valid_nft_count(nft_data)
    }
  end

  def nft_subscriptions(user_id) when is_integer(user_id) do
    User.by_id(user_id)
    |> case do
      {:ok, user} ->
        nft_subscriptions(user)

      {:error, _} ->
        %{
          nft_data: %{},
          has_valid_nft: false,
          nft_count: 0,
          non_valid_nft_count: 0,
          has_non_valid_nft: false
        }
    end
  end

  defp has_valid_nft?(data) do
    data
    |> Enum.filter(fn %{token_ids: token_ids} -> length(token_ids) > 0 end)
    |> Enum.any?()
  end

  defp has_non_valid_nft?(data) do
    data
    |> Enum.filter(fn %{non_valid_token_ids: token_ids} -> length(token_ids) > 0 end)
    |> Enum.any?()
  end

  defp nft_count(data) do
    data
    |> Enum.reduce(0, fn %{token_ids: token_ids}, acc -> acc + length(token_ids) end)
  end

  defp non_valid_nft_count(data) do
    data
    |> Enum.reduce(0, fn %{non_valid_token_ids: non_valid_token_ids}, acc ->
      acc + length(non_valid_token_ids)
    end)
  end
end

defmodule Sanbase.SmartContracts.SanbaseNFT do
  import Sanbase.SmartContracts.Utils,
    only: [call_contract: 4, call_contract_batch: 5, format_address: 1]

  require Logger

  alias Sanbase.Utils.Config

  @contract_goerly "0x7f985e8ad29438907a2cc8ff3d526d9a1693442c"
  @contract_mainnet "0x211E14C8cc67F9EF05cC84F80Dc036Ff2F548949"

  @json_file "sanbase_nft_abi.json"
  @external_resource json_file = Path.join(__DIR__, @json_file)
  @abi File.read!(json_file) |> Jason.decode!()

  # test address with subscriptions: 0x89c276d6e0fda36d7796af0d27a08176cc0f1976
  def abi(), do: @abi

  def contract() do
    case is_dev_or_stage?() do
      true -> @contract_goerly
      false -> @contract_mainnet
    end
  end

  def nft_subscriptions_data(address) do
    tokens_count = balance_of(address)

    if tokens_count > 0 do
      token_ids =
        0..(tokens_count - 1)
        |> Enum.map(fn idx ->
          address = format_address(address)
          execute("tokenOfOwnerByIndex", [address, idx]) |> List.first()
        end)

      valid_token_ids = Enum.filter(token_ids, fn token_id -> execute("isValid", [token_id]) end)
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
    contract_call = fn ->
      call_contract(
        contract(),
        function_abi(function_name),
        args,
        function_abi(function_name).returns
      )
    end

    maybe_replace_goerly(contract_call)
  end

  def execute_batch(function_name, args) do
    contract_call = fn ->
      call_contract_batch(
        contract(),
        function_abi(function_name),
        args,
        function_abi(function_name).returns,
        transform_args_list_fun: fn list -> list ++ ["latest"] end
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
