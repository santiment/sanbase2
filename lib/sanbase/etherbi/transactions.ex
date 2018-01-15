defmodule Sanbase.Etherbi.TransactionsInOut do
  use GenServer

  alias Sanbase.Etherbi.Store

  @default_update_interval 5 * 60_000

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    if Config.get(:sync_enabled, false) do
      Store.create_db()
      update_interval_ms = Config.get(:update_interval, @default_update_interval)

      GenServer.cast(self(), :sync_in)
      GenServer.cast(self(), :sync_out)
      {:ok, %{update_interval_ms: update_interval_ms}}
    end
  end

  def handle_cast(:sync_in, %{update_interval_ms: update_interval_ms} = state) do

    Process.send_after(self(), {:"$gen_cast", :sync}, update_interval_ms)
    {:noreply, state}
  end

  def handle_cast(:sync_in, %{update_interval_ms: update_interval_ms} = state) do

    Process.send_after(self(), {:"$gen_cast", :sync}, update_interval_ms)
    {:noreply, state}
  end
end