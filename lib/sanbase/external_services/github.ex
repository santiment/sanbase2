defmodule Sanbase.ExternalServices.Github do
  @moduledoc """
  # Schedule github scraping jobs

  A GenServer, which on a regular basis looks if the current github activity
  worers are busy and if they are not, schedules scraping jobs for the github
  activity of all the projects that are currently being tracked and has a valid
  github account.
  """
  use GenServer, restart: :permanent, shutdown: 5_000

  import Sanbase.Utils, only: [parse_config_value: 1]

  # 60 minutes
  @default_update_interval 1000 * 60 * 60

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    update_interval = get_config(:update_interval, @default_update_interval)

    if get_config(:sync_enabled, false) do
      Sanbase.Github.Store.create_db()

      GenServer.cast(self(), :sync)

      {:ok, %{update_interval: update_interval}}
    else
      :ignore
    end
  end

  def handle_cast(:sync, %{update_interval: update_interval} = state) do
    Faktory.info
    |> schedule_jobs_if_free

    Process.send_after(self(), {:"$gen_cast", :sync}, update_interval)

    {:noreply, state}
  end

  defp schedule_jobs_if_free(%{"faktory" => %{"total_enqueued" => total_enqueued}}) do
    if total_enqueued > 0 do
      :ok
    else
      Sanbase.Github.Scheduler.schedule_scrape
    end
  end

  defp get_config(key, default) do
    Keyword.get(config(), key, default)
    |> parse_config_value()
  end

  def config do
    Application.get_env(:sanbase, __MODULE__)
  end
end
