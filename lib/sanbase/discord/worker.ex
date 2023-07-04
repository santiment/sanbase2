defmodule Sanbase.Discord.Worker do
  use GenServer
  require Logger

  # Schedule work every 2 minutes
  @schedule_after 120_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    Process.send_after(self(), :work, 1000)
    {:ok, nil}
  end

  def handle_info(:work, state) do
    Logger.info("Warming up...")
    result = Nostrum.Api.get_current_user()
    Logger.info("Warming up result: #{inspect(result)}")

    schedule_work()
    {:noreply, state}
  end

  defp schedule_work() do
    Process.send_after(self(), :work, @schedule_after)
  end
end
