defmodule Sanbase.WalletHunters.Contract do
  require Logger
  import Sanbase.SmartContracts.Utils

  @wallet_hunters_contract "0x772e255402EEE3Fa243CB17AF58001f40Da78d90"
  @abi Path.join(__DIR__, "abis/wallet_hunters_abi.json")
       |> File.read!()
       |> Jason.decode!()
       |> Map.get("abi")

  def abi(), do: @abi

  def function_abi(function) do
    abi()
    |> ABI.parse_specification()
    |> Enum.filter(&(&1.function == function))
    |> hd()
  end

  def event_signature(event_name) do
    abi()
    |> Enum.filter(&(&1["type"] == "event" && &1["name"] == event_name))
    |> hd()
    |> Map.get("signature")
  end

  def get_event_filter_id(event_name) do
    maybe_replace_rinkeby(fn ->
      {:ok, filter_id} =
        Ethereumex.HttpClient.eth_new_filter(%{
          address: @wallet_hunters_contract,
          fromBlock: "0x1",
          toBlock: "latest",
          topics: [event_signature(event_name)]
        })

      filter_id
    end)
  end

  def all_votes() do
    {:ok, events} = fetch_all_events("Voted")

    events
    |> Enum.map(fn event ->
      [_, proposal_id, voter_address] = event["topics"]

      [amount, voted_for] =
        event["data"]
        |> String.slice(2..-1)
        |> Base.decode16!(case: :lower)
        |> ABI.TypeDecoder.decode_raw([{:uint, 256}, :bool])

      %{
        proposal_id: proposal_id |> String.slice(2..-1) |> Integer.parse(16) |> elem(0),
        voter_address: address_strip_zeros(voter_address),
        amount: format_number(amount),
        voted_for: voted_for
      }
    end)
  end

  def fetch_all_events(event_name) do
    maybe_replace_rinkeby(fn ->
      get_event_filter_id(event_name)
      |> Ethereumex.HttpClient.eth_get_filter_logs()
    end)
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
    call_result =
      maybe_replace_rinkeby(fn ->
        call_contract(
          @wallet_hunters_contract,
          function_abi(function_name),
          args,
          function_abi(function_name).returns
        )
      end)

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
    frontend_url = System.get_env("FRONTEND_URL")
    is_binary(frontend_url) && String.contains?(frontend_url, ["stage", "localhost"])
  end

  defp maybe_replace_rinkeby(func) do
    original_url = Application.get_env(:ethereumex, :url)

    # TODO remove after testing on Rinkeby Ethereum Test Network
    if localhost_or_stage?() do
      rinkeby_url = System.get_env("RINKEBY_URL")
      Application.put_env(:ethereumex, :url, rinkeby_url)
    end

    result = func.()

    if localhost_or_stage?() do
      Application.put_env(:ethereumex, :url, original_url)
    end

    result
  end
end
