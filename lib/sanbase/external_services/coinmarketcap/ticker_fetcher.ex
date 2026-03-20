defmodule Sanbase.ExternalServices.Coinmarketcap.TickerFetcher do
  @moduledoc ~s"""
    A GenServer, which updates the data from coinmarketcap on a regular basis.

    Fetches only the current info and no historical data.
    On predefined intervals it will fetch the data from coinmarketcap and insert it
    into a local DB
  """
  use GenServer, restart: :permanent, shutdown: 5_000

  alias Sanbase.Utils.Config
  require Logger

  alias Sanbase.Repo
  alias Sanbase.DateTimeUtils
  alias Sanbase.Project
  alias Sanbase.Model.LatestCoinmarketcapData
  alias Sanbase.ExternalServices.Coinmarketcap.{Ticker, PricePoint}
  alias Sanbase.Price.Validator
  @prices_exporter :prices_exporter

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    if Config.module_get(__MODULE__, :sync_enabled, false) do
      Process.send(self(), :sync, [:noconnect])

      update_interval = Config.module_get(__MODULE__, :update_interval) |> String.to_integer()

      Logger.info(
        "[CMC] Starting TickerFetcher scraper. It will query coinmarketcap every #{update_interval} seconds."
      )

      {:ok, %{update_interval: update_interval}}
    else
      :ignore
    end
  end

  @custom_cmc_slugs ~w[
    bemo-staked-ton
    benqi-liquid-staked-avax
    blazestake-staked-sol
    chain-key-bitcoin
    coinbase-wrapped-staked-eth
    ethena-staked-usde
    ether-fi
    frax-staked-ether
    haedal-staked-sui
    jito-staked-sol
    kelp-dao-restaked-eth
    lido-finance-wsteth
    lido-for-solana
    lido-staked-matic
    liquid-staked-eth
    mantle-staked-ether
    nxm
    renzo-restaked-eth
    restaked-swell-ethereum
    rocket-pool-eth
    santiment
    stader-ethx
    staked-eth
    staked-trx
    staked-wemix
    steth
    volo-staked-sui
    weth
    wmatic
    wrapped-ampleforth
    wrapped-astar
    wrapped-bitcoin
    wrapped-cardano
    wrapped-centrifuge
    wrapped-cro
    wrapped-dog
    wrapped-eeth
    wrapped-everscale
    wrapped-iotex
    wrapped-islamic-coin
    wrapped-mantle
    wrapped-ncg
    wrapped-pulse
    wrapped-tao
    wrapped-tron
    wrapped-xdc-network
    syrup-usdc
    syrup-usdt
    savings-crvusd
  ]
  def work(opts \\ []) do
    Logger.info("[CMC] Fetching realtime data from coinmarketcap")
    # Fetch current coinmarketcap data for many tickers
    # It fetches data for the first N projects, where N is specified in
    # the COINMARKETCAP_API_PROJECTS_NUMBER env var
    {tickers, main_fetch_status} = fetch_main_tickers(opts)

    fetched_slugs = MapSet.new(tickers, & &1.slug)

    # Handle separately tokens that might be out of top N.
    custom_cmc_slugs = @custom_cmc_slugs |> Enum.reject(&(&1 in fetched_slugs))

    # Do not break when some of the handpicked assets is no longer supported.
    # On 03.09.2025 we had an issue where wrapped-fantom started causing HTTP 400
    # which in turn broke everything below {:ok, _} = fetch_data_by_slug
    # and made the exporter fail and did not export the already fetched tickers
    {custom_tickers, custom_fetch_status} =
      fetch_custom_tickers(custom_cmc_slugs, main_fetch_status)

    tickers = tickers ++ custom_tickers

    if tickers == [] and (main_fetch_status != :ok or custom_fetch_status != :ok) do
      Logger.error(
        "[CMC] TickerFetcher: No tickers fetched from any source. " <>
          "Realtime prices will not be updated. Check API key and subscription status."
      )
    end

    # Create a map where the coinmarketcap_id is key and the values is the list of
    # santiment slugs that have that coinmarketcap_id
    cmc_id_to_slugs_mapping = coinmarketcap_to_santiment_slug_map()

    tickers =
      remove_not_valid_prices(tickers, cmc_id_to_slugs_mapping)

    # Create a project if it's a new one in the top projects and we don't have it
    if System.get_env("INSERT_CMC_TOP_N_PROJECTS_INTO_DB") == "1" do
      tickers
      |> Enum.sort_by(& &1.rank, :asc)
      |> Enum.take(top_projects_to_follow())
      |> Enum.each(&insert_or_update_project/1)
    end

    # Store the data in LatestCoinmarketcapData in postgres

    tickers
    |> Enum.each(&store_latest_coinmarketcap_data!/1)

    tickers
    |> export_to_kafka(cmc_id_to_slugs_mapping)

    Logger.info(
      "[CMC] Fetching realtime data from coinmarketcap done. The data is imported in the database."
    )
  end

  defp coinmarketcap_to_santiment_slug_map() do
    Project.List.projects_with_source("coinmarketcap", include_hidden: true)
    |> Enum.reduce(%{}, fn %Project{slug: slug} = project, acc ->
      Map.update(acc, Project.coinmarketcap_id(project), [slug], fn slugs ->
        [slug | slugs]
      end)
    end)
  end

  defp remove_not_valid_prices(tickers, cmc_id_to_slugs_mapping) do
    tickers
    |> Enum.map(fn %{slug: cmc_slug, price_usd: price_usd, price_btc: price_btc} = ticker ->
      case Map.get(cmc_id_to_slugs_mapping, cmc_slug) do
        nil ->
          ticker

        slug ->
          ticker
          |> then(fn t ->
            case Validator.valid_price?(slug, "USD", price_usd) do
              true ->
                t

              {:error, error} ->
                Logger.info("[CMC] Price validation failed: #{inspect(error)}")
                Map.put(t, :price_usd, nil)
            end
          end)
          |> then(fn t ->
            case Validator.valid_price?(slug, "BTC", price_btc) do
              true ->
                t

              {:error, error} ->
                Logger.info("[CMC] Price validation failed: #{inspect(error)}")
                Map.put(t, :price_usd, nil)
            end
          end)
      end
    end)
    |> Enum.filter(fn t -> t.price_usd != nil or t.price_btc != nil end)
  end

  defp export_to_kafka(tickers, cmc_id_to_slugs_mapping) do
    tickers
    |> Enum.flat_map(fn %Ticker{} = ticker ->
      case Map.get(cmc_id_to_slugs_mapping, ticker.slug, []) |> List.wrap() do
        [_ | _] = slugs ->
          # In case of many slugs this means we have multichain assets like tether, a-tether, etc.
          # Use the name of the one with shortest length, i.e. the one without a prefix.
          main_slug = Enum.min_by(slugs, &String.length/1)

          price_point =
            Ticker.to_price_point(ticker)
            |> PricePoint.sanity_filters(main_slug)

          Enum.map(slugs, fn slug ->
            PricePoint.json_kv_tuple(price_point, slug)
          end)

        _ ->
          []
      end
    end)
    |> Sanbase.KafkaExporter.persist_sync(@prices_exporter)
  rescue
    e ->
      Logger.error(
        "[CMC] TickerFetcher: Failed to export to Kafka. Reason: #{Exception.message(e)}"
      )

      Sentry.capture_exception(e,
        stacktrace: __STACKTRACE__,
        extra: %{module: "TickerFetcher", operation: "export_to_kafka"}
      )

      reraise e, __STACKTRACE__
  end

  # Helper functions

  @max_consecutive_failures 10

  def handle_info(:sync, %{update_interval: update_interval} = state) do
    consecutive_failures = Map.get(state, :consecutive_failures, 0)

    state =
      try do
        work()
        Map.put(state, :consecutive_failures, 0)
      rescue
        e ->
          new_failures = consecutive_failures + 1

          Logger.error(
            "[CMC] TickerFetcher.work() crashed (#{new_failures}/#{@max_consecutive_failures}): " <>
              "#{Exception.message(e)}\n" <>
              Exception.format_stacktrace(__STACKTRACE__)
          )

          Sentry.capture_exception(e,
            stacktrace: __STACKTRACE__,
            extra: %{module: "TickerFetcher", consecutive_failures: new_failures}
          )

          if new_failures >= @max_consecutive_failures do
            Logger.error(
              "[CMC] TickerFetcher: #{@max_consecutive_failures} consecutive failures, " <>
                "crashing to let the supervisor restart."
            )

            raise "TickerFetcher exceeded #{@max_consecutive_failures} consecutive failures"
          end

          Map.put(state, :consecutive_failures, new_failures)
      end

    Process.send_after(self(), :sync, update_interval * 1000)

    {:noreply, state}
  end

  defp fetch_main_tickers(opts) do
    case Ticker.fetch_data(opts) do
      {:ok, tickers} ->
        {tickers, :ok}

      {:error, {:auth_error, status, msg}} ->
        Logger.error(
          "[CMC] TickerFetcher: Auth/subscription error (HTTP #{status}). " <>
            "Realtime prices will not be updated. Details: #{msg}"
        )

        {[], :auth_error}

      {:error, {:rate_limited, msg}} ->
        Logger.warning(
          "[CMC] TickerFetcher: Rate limited while fetching ticker data. Details: #{msg}"
        )

        {[], :rate_limited}

      {:error, reason} ->
        Logger.error(
          "[CMC] TickerFetcher: Failed to fetch ticker data. Reason: #{inspect(reason)}"
        )

        {[], :error}
    end
  end

  defp fetch_custom_tickers([], _main_fetch_status), do: {[], :ok}

  defp fetch_custom_tickers(_slugs, :auth_error) do
    Logger.warning(
      "[CMC] TickerFetcher: Skipping custom slug fetch because the main request failed with an auth/subscription error."
    )

    {[], :skipped}
  end

  defp fetch_custom_tickers(_slugs, :rate_limited) do
    Logger.warning(
      "[CMC] TickerFetcher: Skipping custom slug fetch because the main request was rate limited."
    )

    {[], :skipped}
  end

  defp fetch_custom_tickers(slugs, _main_fetch_status) do
    case Ticker.fetch_data_by_slug(slugs) do
      {:ok, custom_tickers} ->
        {custom_tickers, :ok}

      {:error, {:auth_error, _status, _msg}} ->
        {[], :auth_error}

      {:error, reason} ->
        Logger.warning(
          "[CMC] TickerFetcher: Failed to fetch custom slug data. Reason: #{inspect(reason)}"
        )

        {[], :error}
    end
  end

  defp store_latest_coinmarketcap_data!(%Ticker{} = ticker) do
    ticker.slug
    |> LatestCoinmarketcapData.get_or_build()
    |> LatestCoinmarketcapData.changeset(%{
      coinmarketcap_integer_id: ticker.id,
      market_cap_usd: ticker.market_cap_usd,
      name: ticker.name,
      price_usd: ticker.price_usd,
      price_btc: ticker.price_btc,
      rank: ticker.rank,
      volume_usd: ticker.volume_usd,
      available_supply: ticker.available_supply,
      total_supply: ticker.total_supply,
      symbol: ticker.symbol,
      percent_change_1h: ticker.percent_change_1h,
      percent_change_24h: ticker.percent_change_24h,
      percent_change_7d: ticker.percent_change_7d,
      update_time: DateTimeUtils.from_iso8601!(ticker.last_updated)
    })
    |> Repo.insert_or_update!()
  end

  defp insert_or_update_project(%Ticker{slug: slug, name: name, symbol: ticker}) do
    case find_or_init_project(%Project{name: name, slug: slug, ticker: ticker}) do
      {:not_existing_project, changeset} ->
        # If there is not id then the project was not returned from the DB
        # but initialized by the function
        project = changeset |> Repo.insert_or_update!()

        Project.SourceSlugMapping.create(%{
          source: "coinmarketcap",
          slug: project.slug,
          project_id: project.id
        })

      {:existing_project, changeset} ->
        Repo.insert_or_update!(changeset)
    end
  end

  defp find_or_init_project(%Project{slug: slug} = project) do
    case Project.by_slug(slug) do
      nil ->
        {:not_existing_project, Project.changeset(project)}

      existing_project ->
        {:existing_project,
         Project.changeset(existing_project, %{
           slug: slug,
           ticker: project.ticker
         })}
    end
  end

  defp top_projects_to_follow() do
    Config.module_get(__MODULE__, :top_projects_to_follow, "25") |> String.to_integer()
  end
end
