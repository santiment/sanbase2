defmodule Sanbase.ExternalServices.Coinmarketcap2 do
  @moduledoc """
    A GenServer, which updates the data from coinmarketcap on a regular basis.
    On regular intervals it will fetch the data from coinmarketcap and insert it
    into a local DB
  """
  use GenServer, restart: :permanent, shutdown: 5_000

  require Sanbase.Utils.Config, as: Config
  require Logger

  alias Sanbase.Model.Project
  alias Sanbase.Prices.Store
  # TODO: Change
  alias Sanbase.ExternalServices.Coinmarketcap.GraphData2, as: GraphData
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.ExternalServices.Coinmarketcap.ScheduleRescrapePrice
  alias Sanbase.ExternalServices.ProjectInfo

  # 5 minutes
  @default_update_interval 1000 * 60 * 5
  @request_timeout 600_000

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(_arg) do
    if Config.get(:sync_enabled, false) do
      # Create an influxdb if it does not exists, no-op if it exists
      Store.create_db()

      Process.send(self(), :rescrape_prices, [:noconnect])
      Process.send(self(), :fetch_missing_info, [:noconnect])

      # Give `:rescrape_prices` some time to schedule different `last_updated` times
      Process.send_after(self(), :fetch_prices, [:noconnect], 30_000)
      Process.send_after(self(), :fetch_total_market, [:noconnect], 30_000)

      update_interval = Config.get(:update_interval, @default_update_interval)

      # Scrape total market and prices often. Scrape the missing info rarely.
      # There are many projects for which the missing info is not available. The
      # missing info could become available at any time so the scraping attempts
      # should continue. This is made to speed the scraping as the API is rate limited.
      {:ok,
       %{
         missing_info_update_interval: update_interval * 10,
         total_market_update_interval: div(update_interval, 5),
         prices_update_interval: div(update_interval, 5),
         rescrape_prices: update_interval,
         total_market_task_pid: nil
       }}
    else
      :ignore
    end
  end

  def handle_info(:fetch_missing_info, %{missing_info_update_interval: update_interval} = state) do
    Logger.info("[CMC] Fetching missing info for projects.")

    Task.Supervisor.async_stream_nolink(
      Sanbase.TaskSupervisor,
      Project.List.projects(),
      &fetch_project_info/1,
      ordered: false,
      max_concurrency: 1,
      timeout: @request_timeout
    )
    |> Stream.run()

    Process.send_after(self(), :fetch_missing_info, update_interval)
    {:noreply, state}
  end

  def handle_info(
        :fetch_total_market,
        %{
          total_market_update_interval: update_interval,
          total_market_task_pid: total_market_task_pid
        } = state
      ) do
    Logger.info("[CMC] Fetching TOTAL_MARKET data.")

    # If we have a running task for fetching the total market cap do not run it again
    if total_market_task_pid && Process.alive?(total_market_task_pid) do
      {:noreply, state}
    else
      # Start the task under the supervisor in a way that does not need await.
      # As there is only one data record to be fetched we fire and forget about it,
      # so the work can continue to scraping the projects' prices in parallel.
      {:ok, pid} =
        Task.Supervisor.start_child(
          Sanbase.TaskSupervisor,
          &fetch_and_process_marketcap_total_data/0
        )

      Process.send_after(self(), :fetch_total_market, update_interval)
      {:noreply, Map.put(state, :total_market_task_pid, pid)}
    end
  end

  def handle_info(:fetch_prices, %{prices_update_interval: update_interval} = state) do
    Logger.info("[CMC] Fetching prices for projects.")

    # Run the tasks in a stream concurrently so `max_concurrency` can be used.
    # Otherwise risking to start too many tasks to a service that's rate limited
    Task.Supervisor.async_stream_nolink(
      Sanbase.TaskSupervisor,
      Project.List.projects(),
      &fetch_and_process_price_data/1,
      ordered: false,
      max_concurrency: 2,
      timeout: @request_timeout
    )
    |> Stream.run()

    Process.send_after(self(), :fetch_prices, update_interval)
    {:noreply, state}
  end

  def handle_info(:rescrape_prices, %{rescrape_prices: update_interval} = state) do
    finish_rescrapes()
    schedule_rescrapes()
    Process.send_after(self(), :fetch_prices, update_interval)

    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.warn("[CMC] Unknown message received in #{__MODULE__}: #{msg}")
    {:noreply, state}
  end

  defp finish_rescrapes() do
    rescrapes = ScheduleRescrapePrice.all_in_progress()

    for %ScheduleRescrapePrice{project: project} = srp <- rescrapes do
      last_updated = Store.last_history_datetime_cmc(Measurement.name_from(project))
      {srp, last_updated}
    end
  end

  # For all rescrapes that are not started the following will be done:
  # 1. If there is a running task for scraping it, it will be killed
  # 2. The `last_updated` time will be fetched and recorded in the database so it can be later restored
  # 3. Set the `last_updated` time to the scheduled `from`
  defp schedule_rescrapes() do
    rescrapes = ScheduleRescrapePrice.all_not_started()

    for %ScheduleRescrapePrice{project: project, from: from} = srp <- rescrapes do
      case Registry.lookup(Sanbase.Registry, fetching_price_registry_key(project)) do
        [{pid, :running}] ->
          Process.exit(pid, :kill)

        _ ->
          :ok
      end

      Store.update_last_history_datetime_cmc(Measurement.name_from(project), from)

      srp
      |> ScheduleRescrapePrice.set_original_last_updated()
      |> ScheduleRescrapePrice.changeset(%{in_progress: true})
      |> ScheduleRescrapePrice.update()
    end
  end

  # Private functions

  # Fetch project info from Coinmarketcap and Etherscan. Fill only missing info
  # and does not override existing info.
  defp fetch_project_info(%Project{} = project) do
    if ProjectInfo.project_info_missing?(project) do
      Logger.info(
        "[CMC] There is missing info for #{Project.describe(project)}. Will try to fetch it."
      )

      ProjectInfo.from_project(project)
      |> ProjectInfo.fetch_coinmarketcap_info()
      |> case do
        {:ok, project_info_with_coinmarketcap_info} ->
          project_info_with_coinmarketcap_info
          |> ProjectInfo.fetch_etherscan_token_summary()
          |> ProjectInfo.fetch_contract_info()
          |> ProjectInfo.update_project(project)

        _ ->
          nil
      end
    end
  end

  defp fetching_price_registry_key(project) do
    measurement_name = Measurement.name_from(project)
    {:cmc_fetch_price, measurement_name}
  end

  # Fetch history coinmarketcap data and store it in DB
  defp fetch_and_process_price_data(
         %Project{coinmarketcap_id: coinmarketcap_id, ticker: ticker} = project
       )
       when nil != ticker and nil != coinmarketcap_id do
    measurement_name = Measurement.name_from(project)
    key = fetching_price_registry_key(project)

    if Registry.lookup(Sanbase.Registry, key) == [] do
      Registry.register(Sanbase.Registry, key, {:running, self()})
      Logger.info("Fetch and process prices for #{measurement_name}")

      case last_price_datetime(project) do
        nil ->
          err_msg =
            "[CMC] Cannot fetch the last price datetime for #{coinmarketcap_id} with ticker #{
              ticker
            }"

          Logger.warn(err_msg)
          {:error, err_msg}

        last_price_datetime ->
          Logger.info(
            "[CMC] Latest price datetime for #{measurement_name} - " <>
              inspect(last_price_datetime)
          )

          GraphData.fetch_and_store_prices(project, last_price_datetime)

          process_notifications(project)
          Registry.unregister(Sanbase.Registry, key)
          :ok
      end
    else
      Logger.info(
        "[CMC] Fetch and process job for #{measurement_name} is already running. Won't start it again"
      )
    end
  end

  defp process_notifications(%Project{} = project) do
    Sanbase.Notifications.PriceVolumeDiff.exec(project, "USD")
  end

  defp last_price_datetime(%Project{coinmarketcap_id: coinmarketcap_id} = project) do
    measurement_name = Measurement.name_from(project)

    case Store.last_history_datetime_cmc!(measurement_name) do
      nil ->
        Logger.info(
          "[CMC] Last CMC history datetime scraped for #{measurement_name} not found in the database."
        )

        GraphData.fetch_first_datetime(coinmarketcap_id)

      datetime ->
        datetime
    end
  end

  defp last_marketcap_total_datetime() do
    measurement_name = "TOTAL_MARKET_total-market"

    case Store.last_history_datetime_cmc!(measurement_name) do
      nil ->
        Logger.info(
          "[CMC] Last CMC history datetime scraped for #{measurement_name} not found in the database."
        )

        GraphData.fetch_first_datetime(measurement_name)

      datetime ->
        datetime
    end
  end

  defp fetch_and_process_marketcap_total_data() do
    case last_marketcap_total_datetime() do
      nil ->
        err_msg = "[CMC] Cannot fetch the last price datetime for TOTAL_MARKET"
        Logger.warn(err_msg)
        {:error, err_msg}

      last_price_datetime ->
        GraphData.fetch_and_store_marketcap_total(last_price_datetime)
        :ok
    end
  end
end
