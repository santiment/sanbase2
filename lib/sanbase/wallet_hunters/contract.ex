defmodule Sanbase.WalletHunters.Contract do
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

  def wallet_proposals(limit \\ nil, offset \\ 0) do
    args = [offset, limit || wallet_proposals_count()]

    contract_execute("walletProposals", args)
  end

  def wallet_proposal(proposal_id) do
    contract_execute("walletProposal", [proposal_id])
  end

  def contract_execute(function_name, args) do
    call_contract(
      @wallet_hunters_contract,
      function_abi(function_name),
      args,
      function_abi(function_name).returns
    )
    |> case do
      {:error, %{"message" => message}} ->
        {:error, message}

      {:error, reason} ->
        {:error, "Error during executing smart contract call"}

      [result | _] ->
        result
    end
  end
end
