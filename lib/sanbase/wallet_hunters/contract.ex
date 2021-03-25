defmodule Sanbase.WalletHunters.Contract do
  import Sanbase.SmartContracts.Utils

  @contract "0x772e255402EEE3Fa243CB17AF58001f40Da78d90"
  @abi Path.join(__DIR__, "abis/wallet_hunters_abi.json")

  def abi do
    File.read!(@abi)
    |> Jason.decode!()
    |> Map.get("abi")
  end

  def function_abi(function) do
    abi()
    |> ABI.parse_specification()
    |> Enum.filter(&(&1.function == function))
    |> hd()
  end

  def wallet_proposals_count() do
    call_contract(
      @contract,
      function_abi("walletProposalsLength"),
      [],
      function_abi("walletProposalsLength").returns
    )
    |> hd()
  end

  def wallet_proposals(limit \\ nil, offset \\ 0) do
    args = [offset, limit || wallet_proposals_count()]

    call_contract(
      @contract,
      function_abi("walletProposals"),
      args,
      function_abi("walletProposals").returns
    )
    |> hd()
  end

  def wallet_proposal(proposal_id) do
    call_contract(
      @contract,
      function_abi("walletProposal"),
      [proposal_id],
      function_abi("walletProposal").returns
    )
  end
end
