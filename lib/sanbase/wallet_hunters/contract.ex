defmodule Sanbase.WalletHunters.Contract do
  import Sanbase.SmartContracts.Utils
  require Logger

  @abi_file Path.join(__DIR__, "abis/wallet_hunters_abi.json")
            |> File.read!()
            |> Jason.decode!()

  @abi Map.get(@abi_file, "abi")
  @rinkeby_contract get_in(@abi_file, ["networks", "rinkeby", "address"]) ||
                      raise("Missing wallet hunters Rinkeby address.")
  @ropsten_contract get_in(@abi_file, ["networks", "ropsten", "address"]) ||
                      raise("Missing wallet hunters Ropsten address.")
  @mainnet_contract get_in(@abi_file, ["networks", "mainnet", "address"]) ||
                      raise("Missing wallet hunters Mainnet address.")

  def contract() do
    if localhost_or_stage?(), do: @rinkeby_contract, else: @mainnet_contract
  end

  def rinkeby_contract(), do: @rinkeby_contract
  def ropsten_contract(), do: @ropsten_contract
  def mainnet_contract(), do: @mainnet_contract
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

  def get_trx_by_id(trx_id) do
    maybe_replace_rinkeby(
      fn ->
        Logger.info("[EthNode] Get eth transaction by hash via Ethereumex client.")
        Ethereumex.HttpClient.eth_get_transaction_by_hash(trx_id)
      end,
      :eth_get_transaction_by_hash
    )
  end

  def get_trx_receipt_by_id(trx_id) do
    maybe_replace_rinkeby(
      fn ->
        Logger.info("[EthNode] Get eth transaction receipt via Ethereumex client.")
        Ethereumex.HttpClient.eth_get_transaction_receipt(trx_id)
      end,
      :eth_get_transaction_receipt
    )
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
    maybe_replace_rinkeby(
      fn ->
        Logger.info("[EthNode] Call eth_get_logs via Ethereumex client.")
        Ethereumex.HttpClient.eth_get_logs(%{topics: [event_signature(event_name)]})
      end,
      :fetch_all_events
    )
  end

  def wallet_proposals_count() do
    contract_execute("walletProposalsLength", [])
  end

  def wallet_proposals() do
    count = wallet_proposals_count()

    if is_integer(count) and count > 0 do
      case contract_execute("walletProposals", [0, count]) do
        {:error, _} -> []
        result -> result
      end
    else
      []
    end
  end

  def wallet_proposal(proposal_id) do
    contract_execute("walletProposal", [proposal_id])
  end

  def contract_execute(function_name, args) do
    call_result =
      maybe_replace_rinkeby(
        fn ->
          call_contract(
            contract(),
            function_abi(function_name),
            args,
            function_abi(function_name).returns
          )
        end,
        function_name
      )

    call_result
    |> case do
      {:error, %{"message" => message}} ->
        {:error, message}

      {:error, reason} ->
        Logger.error(
          "Error occurred during executing smart contract call #{function_name} with args: #{inspect(args)}. reason: #{inspect(reason)}"
        )

        {:error, "Error occured during executing smart contract call"}

      [result | _] ->
        result
    end
  end

  # TODO - remove after testing on Rinkeby Ethereum Test Network
  defp maybe_replace_rinkeby(func, func_name) do
    maybe_put_rinkeby_url()

    try do
      {elapsed, result} = :timer.tc(fn -> func.() end)

      Logger.info("Contract call: #{func_name}, elapsed: #{elapsed / 1_000_000}")

      result
    rescue
      e ->
        Logger.error("Error occurred while executing smart contract call: #{inspect(e)}")

        {:error, "Error occurred while executing smart contract call."}
    after
      maybe_put_parity_url()
    end
  end

  defp maybe_put_rinkeby_url() do
    if localhost_or_stage?() do
      rinkeby_url = System.get_env("RINKEBY_URL")
      Application.put_env(:ethereumex, :url, rinkeby_url)
    end
  end

  defp maybe_put_parity_url() do
    if localhost_or_stage?() do
      Application.put_env(:ethereumex, :url, System.get_env("PARITY_URL"))
    end
  end

  defp localhost_or_stage? do
    frontend_url = SanbaseWeb.Endpoint.frontend_url()

    is_binary(frontend_url) &&
      String.contains?(frontend_url, ["stage", "localhost"])
  end
end
