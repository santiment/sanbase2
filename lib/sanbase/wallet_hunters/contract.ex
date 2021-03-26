defmodule Sanbase.WalletHunters.Contract do
  require Logger
  import Sanbase.SmartContracts.Utils

  @wallet_hunters_contract "0x772e255402EEE3Fa243CB17AF58001f40Da78d90"
  @abi Path.join(__DIR__, "abis/wallet_hunters_abi.json")

  def abi do
    Sanbase.Cache.get_or_store(
      {__MODULE__, :wallet_hunters_abi} |> Sanbase.Cache.hash(),
      fn ->
        File.read!(@abi)
        |> Jason.decode!()
        |> Map.get("abi")
      end
    )
  end

  def function_abi(function) do
    abi()
    |> ABI.parse_specification()
    |> Enum.filter(&(&1.function == function))
    |> hd()
  end

  def wallet_proposals_count() do
    contract_execute("walletProposalsLength", [])
  end

  def wallet_proposals() do
    count = wallet_proposals_count()

    if count > 0 do
      contract_execute("walletProposals", [0, count])
    else
      []
    end
  end

  def wallet_proposal(proposal_id) do
    contract_execute("walletProposal", [proposal_id])
  end

  def contract_execute(function_name, args) do
    original_url = Application.get_env(:ethereumex, :url)

    # TODO remove after testing on Rinkeby Ethereum Test Network
    if localhost_or_stage?() do
      rinkeby_url = System.get_env("RINKEBY_URL")
      Application.put_env(:ethereumex, :url, rinkeby_url)
    end

    call_result =
      call_contract(
        @wallet_hunters_contract,
        function_abi(function_name),
        args,
        function_abi(function_name).returns
      )

    if localhost_or_stage?() do
      Application.put_env(:ethereumex, :url, original_url)
    end

    call_result
    |> case do
      {:error, %{"message" => message}} ->
        {:error, message}

      {:error, reason} ->
        Logger.error(
          "Error occurred during executing smart contract call #{function_name} with args: #{
            inspect(args)
          }. reason: #{inspect(reason)}"
        )

        {:error, "Error occured during executing smart contract call"}

      [result | _] ->
        result
    end
  end

  def localhost_or_stage? do
    System.get_env("FRONTEND_URL") |> String.contains?(["stage", "localhost"])
  end
end
