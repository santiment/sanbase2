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


  @default_update_interval_ms 1000 * 60 * 5
  @average_block_time_ms 10000 #Actually it's close to 15s
  @default_timespan_ms 7*24*60*60*1000 # 1 week

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    Logger.info fn ->
      "Starting etherscan polling client"
    end
    
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
    endblock = Requests.get_latest_block_number()
    #startblock = endblock - Float.ceil(@default_timespan_ms/@average_block_time_ms)
    startblock = 0
    
    TrackedEth
    |> Repo.all
    |> Enum.each(&(fetch_and_store(&1, startblock, endblock)))

    Process.send_after(self(), {:"$gen_cast", :sync}, update_interval_ms)

    {:noreply, state}
  end

  def config do
    Application.get_env(:sanbase, __MODULE__)
  end

  defp fetch(address, startblock, endblock) do
    changeset = %{
      update_time: NaiveDateTime.utc_now,
      balance: Balance.get(address).result
    }

    case Tx.get_last_outgoing_transaction(address, startblock, endblock) do
      %Tx{timeStamp: ts, value: value}-> Map.merge(changeset,
        %{ 
	  last_outgoing: NaiveDateTime.add(~N[1970-01-01 00:00:00], ts),
	  tx_out: value
         })
      nil -> changeset
    end
  end

  defp fetch_and_store(%TrackedEth{address: address}, startblock, endblock) do
    changeset = fetch(address, startblock, endblock)

    get_or_create_entry(address)
    |> LatestEthWalletData.changeset(changeset)
    |> Repo.insert_or_update!
  end

  defp get_or_create_entry(address) do
    case Repo.get(LatestEthWalletData, address) do
      nil -> %LatestEthWalletData{address: address}
      entry -> entry
    end
  end
    
end
