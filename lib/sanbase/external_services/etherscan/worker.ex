defmodule Sanbase.ExternalServices.Etherscan.Worker do
  # A worker that regularly polls etherscan for tracked addresses and
  # updates the last outgoing transactions in the database

  use GenServer, restart: :permanent, shutdown: 5_000
  require Logger

  alias Sanbase.Model.LatestEthWalletData
  alias Sanbase.Model.TrackedEth
  alias Sanbase.Repo
  alias Sanbase.ExternalServices.Etherscan.Requests
  alias Sanbase.ExternalServices.Etherscan.Requests.{Balance, Tx}

  alias Decimal, as: D

  @default_update_interval_ms 1000 * 60 * 5
  @average_block_time_ms 10000 #Actually it's close to 15s
  @default_timespan_ms 30*24*60*60*1000 # 30 days
  @confirmations 10

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    Logger.info "Starting etherscan polling client"

    # Trap exists, so that we don't die when a child dies
    Process.flag(:trap_exit, true)

    # For calculating balance in eth (to keep functionality same as
    # old sanbase)
    D.set_context %{D.get_context | precision: 2}

    update_interval_ms = Keyword.get(config(), :update_interval_ms, @default_update_interval_ms)

    if Keyword.get(config(), :sync_enabled, false) do
      GenServer.cast(self(), :sync)

      {:ok, %{update_interval_ms: update_interval_ms}}
    else
      :ignore
    end
  end

  def handle_cast(:sync, %{update_interval_ms: update_interval_ms} = state) do
    #1. Get current block number
    endblock = Requests.get_latest_block_number() - @confirmations
    startblock = endblock - Float.ceil(@default_timespan_ms/@average_block_time_ms)

    Repo.all(TrackedEth)
    |> Task.async_stream(
      &fetch_and_store(&1, startblock, endblock),
      max_concurrency: 5,
      on_timeout: :kill_task,
      ordered: false,
      timeout: 30_000)
    |> Stream.run

    Process.send_after(self(), {:"$gen_cast", :sync}, update_interval_ms)

    {:noreply, state}
  end

  def config do
    Application.get_env(:sanbase, __MODULE__)
  end


  defp convert_to_eth(wei) do
    D.div(D.new(wei), D.new(1000000000000000000))
  end

  def fetch(address, startblock, endblock) do
    changeset = %{
      update_time: DateTime.utc_now,
      balance: convert_to_eth(Balance.get(address).result)
    }

    case Tx.get_last_outgoing_transaction(address, startblock, endblock) do
      %Tx{timeStamp: ts, value: value}-> Map.merge(changeset,
        %{
          last_outgoing: DateTime.from_unix!(ts),
          tx_out: convert_to_eth(value)
         })
      nil -> changeset
    end
  end

  def fetch_and_store(%TrackedEth{address: address}, startblock, endblock) do
    Logger.info("Updating transactions of address #{address}")
    changeset = fetch(address, startblock, endblock)
    get_or_create_entry(address)
    |> LatestEthWalletData.changeset(changeset)
    |> Repo.insert_or_update!
  end

  defp get_or_create_entry(address) do
    case Repo.get_by(LatestEthWalletData, address: address) do
      nil -> %LatestEthWalletData{address: address}
      entry -> entry
    end
  end

end
