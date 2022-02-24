defmodule Sanbase.ExternalServices.Coinmarketcap do
  @moduledoc """
    A GenServer, which updates the data from coinmarketcap on a regular basis.
    On regular intervals it will fetch the data from coinmarketcap and insert it
    into a local DB
  """
  use GenServer, restart: :permanent, shutdown: 5_000

  require Sanbase.Utils.Config, as: Config
  require Logger

  alias Sanbase.Model.LatestCoinmarketcapData
  alias Sanbase.Model.Project

  alias Sanbase.ExternalServices.Coinmarketcap.{
    WebApi,
    ScheduleRescrapePrice,
    PriceScrapingProgress
  }

  alias Sanbase.ExternalServices.ProjectInfo

  @request_timeout 600_000
  @source "coinmarketcap"

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(_arg) do
    if Config.get(:sync_enabled, false) do
      Process.send(self(), :rescrape_prices, [])

      # Give `:rescrape_prices` some time to schedule different `last_updated` times
      Process.send_after(self(), :fetch_total_market, 15_000)
      Process.send_after(self(), :fetch_prices, 20_000)
      Process.send_after(self(), :fetch_missing_info, 25_000)

      update_interval = Config.get(:update_interval)

      # Scrape total market and prices often. Scrape the missing info rarely.
      # There are many projects for which the missing info is not available. The
      # missing info could become available at any time so the scraping attempts
      # should continue. This is made to speed the scraping as the API is rate limited.
      {:ok,
       %{
         missing_info_update_interval: update_interval * 10,
         total_market_update_interval: update_interval,
         prices_update_interval: update_interval,
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
      Project.List.projects_with_source("coinmarketcap",
        include_hidden: true,
        order_by_rank: true
      ),
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
          &fetch_total_market_data/0
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
      Project.List.projects(include_hidden: true, order_by_rank: true),
      &fetch_prices/1,
      ordered: false,
      max_concurrency: 2,
      timeout: @request_timeout
    )
    |> Stream.run()

    Process.send_after(self(), :fetch_prices, update_interval)
    {:noreply, state}
  end

  def handle_info(:rescrape_prices, %{rescrape_prices: update_interval} = state) do
    schedule_rescrapes()
    finish_rescrapes()
    Process.send_after(self(), :rescrape_prices, update_interval)

    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.warn("[CMC] Unknown message received in #{__MODULE__}: #{msg}")
    {:noreply, state}
  end

  # Private functions

  # For all rescrapes that are not started the following will be done:
  # 1. If there is a running task for scraping that project it will be killed
  # 2. The `last_updated` time will be fetched and recorded in the database so it can be later restored
  # 3. Set the `last_updated` time to the scheduled `from`
  defp schedule_rescrapes() do
    rescrapes = ScheduleRescrapePrice.all_not_started()
    Logger.info("[CMC] Check if project price rescraping need to be scheduled.")

    if rescrapes != [] do
      Logger.info("[CMC] Price rescraping will be scheduled for #{length(rescrapes)} projects.")
    end

    for %ScheduleRescrapePrice{project: project, from: from} = srp <- rescrapes do
      {:ok, original_last_updated} =
        case PriceScrapingProgress.last_scraped(project.slug, @source) do
          nil -> WebApi.first_datetime(project)
          %DateTime{} = dt -> {:ok, dt}
        end

      kill_scheduled_scraping(project)

      {:ok, _} = PriceScrapingProgress.store_progress(project.slug, @source, from)

      srp
      |> ScheduleRescrapePrice.changeset(%{
        in_progress: true,
        finished: false,
        original_last_updated: original_last_updated
      })
      |> ScheduleRescrapePrice.update()
    end
  end

  defp finish_rescrapes() do
    Logger.info(
      "[CMC] Check if project price rescraping is done and the original `last_updated` timestamp will be returned."
    )

    rescrapes = ScheduleRescrapePrice.all_in_progress()

    for %ScheduleRescrapePrice{} = srp <- rescrapes do
      maybe_mark_rescrape_as_finished(srp)
      maybe_remove_impossible_rescrape(srp)
      maybe_restart_lost_scrape(srp)
    end
  end

  defp maybe_mark_rescrape_as_finished(%ScheduleRescrapePrice{} = srp) do
    %ScheduleRescrapePrice{project: project, to: to} = srp

    to = DateTime.from_naive!(to, "Etc/UTC")
    last_updated = PriceScrapingProgress.last_scraped(project.slug, @source)

    if last_updated && DateTime.compare(last_updated, to) == :gt do
      mark_rescrape_as_finished(srp)
    end
  end

  defp mark_rescrape_as_finished(%ScheduleRescrapePrice{} = srp) do
    %ScheduleRescrapePrice{project: project} = srp

    kill_scheduled_scraping(project)

    {:ok, original_last_update} = srp.original_last_updated |> DateTime.from_naive("Etc/UTC")

    PriceScrapingProgress.store_progress(project.slug, @source, original_last_update)

    srp
    |> ScheduleRescrapePrice.changeset(%{finished: true, in_progress: false})
    |> ScheduleRescrapePrice.update()
  end

  defp maybe_remove_impossible_rescrape(srp) do
    case LatestCoinmarketcapData.coinmarketcap_integer_id(srp.project) do
      nil ->
        # If the project does not have a coinmarketcap integer id the rescrape
        # can not be done. Just mark it as finished in this case
        mark_rescrape_as_finished(srp)

      _ ->
        :ok
    end
  end

  defp maybe_restart_lost_scrape(srp) do
    case project_rescrape_registry_entry(srp.project) do
      [{:running, _pid}] ->
        :ok

      [] ->
        # if we reach here, then this is a rescrape in progress for which there is
        # no running task.
        do_fetch_prices(srp.project)
    end
  end

  # Fetch project info from Coinmarketcap and Etherscan. Fill only missing info
  # and does not override existing info.
  defp fetch_project_info(%Project{} = project) do
    if ProjectInfo.project_info_missing?(project) do
      Logger.info(
        "[CMC] There is missing info for #{Project.describe(project)}. Will try to fetch it."
      )

      ProjectInfo.from_project(project)
      |> ProjectInfo.fetch_from_ethereum_node()
      |> ProjectInfo.fetch_coinmarketcap_info()
      |> ProjectInfo.update_project(project)
    end
  end

  # Fetch history
  defp fetch_prices(%Project{} = project) do
    cmc_id = Project.coinmarketcap_id(project)
    %Project{slug: slug, ticker: ticker} = project

    if cmc_id != nil and slug != nil and ticker != nil do
      do_fetch_prices(project)
    else
      :ok
    end
  end

  defp do_fetch_prices(project) do
    key = price_scraping_registry_key(project)

    if Registry.lookup(Sanbase.Registry, key) == [] do
      Registry.register(Sanbase.Registry, key, :running)
      Logger.info("Fetch and process prices for #{project.slug}")

      case last_price_datetime(project) do
        {:ok, datetime} ->
          Logger.info(
            "[CMC] Latest price datetime for #{Project.describe(project)} - #{datetime}"
          )

          WebApi.fetch_and_store_prices(project, datetime)

          Registry.unregister(Sanbase.Registry, key)
          :ok

        _ ->
          err_msg = "[CMC] Cannot fetch the last price datetime for project #{project.slug}"

          Logger.warn(err_msg)
          {:error, err_msg}
      end
    else
      Logger.info(
        "[CMC] Fetch and process job for project #{project.slug} is already running. Won't start it again"
      )
    end
  end

  defp price_scraping_registry_key(project) do
    {:cmc_fetch_history_price, project.id}
  end

  defp last_price_datetime(%Project{} = project) do
    case PriceScrapingProgress.last_scraped(project.slug, @source) do
      nil ->
        Logger.info(
          "[CMC] Last CMC history datetime scraped for project with slug #{project.slug} not found in the database."
        )

        WebApi.first_datetime(project)

      %DateTime{} = datetime ->
        {:ok, datetime}
    end
  end

  defp last_price_datetime("TOTAL_MARKET") do
    case PriceScrapingProgress.last_scraped("TOTAL_MARKET", @source) do
      nil ->
        Logger.info(
          "[CMC] Last CMC history datetime scraped for TOTAL_MARKET not found in the database."
        )

        WebApi.first_datetime("TOTAL_MARKET")

      %DateTime{} = datetime ->
        {:ok, datetime}
    end
  end

  defp fetch_total_market_data() do
    case last_price_datetime("TOTAL_MARKET") do
      {:ok, %DateTime{} = datetime} ->
        WebApi.fetch_and_store_prices("TOTAL_MARKET", datetime)
        :ok

      _ ->
        err_msg = "[CMC] Cannot fetch the last price datetime for TOTAL_MARKET"
        Logger.warn(err_msg)
        {:error, err_msg}
    end
  end

  defp project_rescrape_registry_entry(project) do
    Registry.lookup(Sanbase.Registry, price_scraping_registry_key(project))
  end

  defp kill_scheduled_scraping(project) do
    case project_rescrape_registry_entry(project) do
      [{pid, :running}] -> Process.exit(pid, :kill)
      _ -> :ok
    end
  end
end
