defmodule Sanbase.ExternalServices.Coinmarketcap do
  @moduledoc """
    A GenServer, which updates the data from coinmarketcap on a regular basis.
    On regular intervals it will fetch the data from coinmarketcap and insert it
    into a local DB
  """
  use GenServer, restart: :permanent, shutdown: 5_000

  alias Sanbase.Utils.Config
  require Logger

  alias Sanbase.Project
  alias Sanbase.ExternalServices.Coinmarketcap.{WebApi, PriceScrapingProgress}

  alias Sanbase.ExternalServices.ProjectInfo

  @request_timeout 600_000
  @source "coinmarketcap"

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(_arg) do
    if Config.module_get(__MODULE__, :sync_enabled, false) do
      Process.send_after(self(), :fetch_total_market, 15_000)
      Process.send_after(self(), :fetch_prices, 20_000)
      Process.send_after(self(), :fetch_missing_info, 25_000)

      update_interval = Config.module_get(__MODULE__, :update_interval)

      # Scrape total market and prices often. Scrape the missing info rarely.
      # There are many projects for which the missing info is not available. The
      # missing info could become available at any time so the scraping attempts
      # should continue. This is made to speed the scraping as the API is rate limited.
      #
      # The price rescrapes are not done here, see `RescrapeScheduler`.
      {:ok,
       %{
         missing_info_update_interval: update_interval * 10,
         total_market_update_interval: update_interval,
         prices_update_interval: update_interval,
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
      Process.send_after(self(), :fetch_total_market, update_interval)
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

  def handle_info(msg, state) do
    Logger.warning("[CMC] Unknown message received in #{__MODULE__}: #{inspect(msg)}")
    {:noreply, state}
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

    # The registry lock guards against scraping the same project concurrently,
    # e.g. by a run started by a restarted GenServer while the old one still runs
    case Registry.register(Sanbase.Registry, key, :running) do
      {:ok, _} ->
        Logger.info("[CMC] Fetch and process prices for #{project.slug}")
        fetch_and_store_prices_and_unregister(project, key)

      {:error, {:already_registered, _}} ->
        Logger.info(
          "[CMC] Fetch and process job for project #{project.slug} is already running. Won't start it again"
        )
    end
  end

  defp fetch_and_store_prices_and_unregister(project, key) do
    with {:ok, datetime} <- last_price_datetime(project),
         :ok <- WebApi.fetch_and_store_prices(project, datetime) do
      :ok
    else
      error ->
        Logger.error("[CMC] Error fetching prices for #{project.slug}: #{inspect(error)}")
        error
    end
  after
    # Run the unregister both in cases of no-exception and exception
    Registry.unregister(Sanbase.Registry, key)
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

        # If we have not scraped this project, then we should start from the beginning.
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
    with {:ok, %DateTime{} = datetime} <- last_price_datetime("TOTAL_MARKET"),
         :ok <- WebApi.fetch_and_store_prices("TOTAL_MARKET", datetime) do
      :ok
    else
      error ->
        Logger.error("[CMC] Error fetching TOTAL_MARKET data: #{inspect(error)}")
        error
    end
  end
end
