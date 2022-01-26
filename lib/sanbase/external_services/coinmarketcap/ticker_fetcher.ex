defmodule Sanbase.ExternalServices.Coinmarketcap.TickerFetcher do
  @moduledoc ~s"""
    A GenServer, which updates the data from coinmarketcap on a regular basis.

    Fetches only the current info and no historical data.
    On predefined intervals it will fetch the data from coinmarketcap and insert it
    into a local DB
  """
  use GenServer, restart: :permanent, shutdown: 5_000

  require Sanbase.Utils.Config, as: Config
  require Logger

  alias Sanbase.Repo
  alias Sanbase.DateTimeUtils
  alias Sanbase.Model.{LatestCoinmarketcapData, Project}
  alias Sanbase.ExternalServices.Coinmarketcap.{Ticker, PricePoint}
  alias Sanbase.Prices.Store

  @prices_exporter :prices_exporter

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    if Config.get(:sync_enabled, false) do
      Store.create_db()

      Process.send(self(), :sync, [:noconnect])

      update_interval = Config.get(:update_interval) |> String.to_integer()

      Logger.info(
        "[CMC] Starting TickerFetcher scraper. It will query coinmarketcap every #{update_interval} seconds."
      )

      {:ok, %{update_interval: update_interval}}
    else
      :ignore
    end
  end

  def work(opts \\ []) do
    Logger.info("[CMC] Fetching realtime data from coinmarketcap")
    # Fetch current coinmarketcap data for many tickers
    {:ok, tickers} = Ticker.fetch_data(opts)

    # Create a map where the coinmarketcap_id is key and the values is the list of
    # santiment slugs that have that coinmarketcap_id
    cmc_id_to_slugs_mapping = coinmarketcap_to_santiment_slug_map()

    tickers = remove_not_valid_prices(tickers, cmc_id_to_slugs_mapping)

    # Create a project if it's a new one in the top projects and we don't have it
    tickers
    |> Enum.take(top_projects_to_follow())
    |> Enum.each(&insert_or_update_project/1)

    # Store the data in LatestCoinmarketcapData in postgres

    tickers
    |> Enum.each(&store_latest_coinmarketcap_data!/1)

    # Store the data in Influxdb
    if Application.get_env(:sanbase, :influx_store_enabled, true) do
      tickers
      |> Enum.flat_map(&Ticker.convert_for_importing(&1, cmc_id_to_slugs_mapping))
      |> Store.import()
    end

    tickers
    |> export_to_kafka(cmc_id_to_slugs_mapping)

    Logger.info(
      "[CMC] Fetching realtime data from coinmarketcap done. The data is imported in the database."
    )
  end

  defp coinmarketcap_to_santiment_slug_map() do
    Project.List.projects_with_source("coinmarketcap", include_hidden: true)
    |> Enum.reduce(%{}, fn %Project{slug: slug} = project, acc ->
      Map.update(acc, Project.coinmarketcap_id(project), [slug], fn slugs -> [slug | slugs] end)
    end)
  end

  defp remove_not_valid_prices(tickers, cmc_id_to_slugs_mapping) do
    tickers
    |> Enum.each(fn %{slug: cmc_slug, price_usd: price_usd, price_btc: price_btc} ->
      # This implementation does not remove/change anything. It will be deployed first
      # so we can observe the behaviour first.
      slug = Map.get(cmc_id_to_slugs_mapping, cmc_slug)

      case Sanbase.Price.Validator.valid_price?(slug, "USD", price_usd) do
        {:error, error} -> Logger.info("[CMC] Price validation failed: #{error}")
        _ -> :ok
      end

      case Sanbase.Price.Validator.valid_price?(slug, "BTC", price_btc) do
        {:error, error} -> Logger.info("[CMC] Price validation failed: #{error}")
        _ -> :ok
      end
    end)

    tickers
  end

  # TODO: Revert to this implementation after we the debug implementation is
  # tested and all potential issues are fixed
  # defp remove_not_valid_prices(tickers, cmc_id_to_slugs_mapping) do
  #   tickers
  #   |> Enum.map(fn %{slug: cmc_slug, price_usd: price_usd, price_btc: price_btc} = ticker ->
  #     slug = Map.get(cmc_id_to_slugs_mapping, cmc_slug)

  #     ticker
  #     |> then(fn t ->
  #       if true == Sanbase.Price.Validator.valid_price?(slug, "USD", price_usd),
  #         do: t,
  #         else: Map.put(t, :price_usd, nil)
  #     end)
  #     |> then(fn t ->
  #       if true == Sanbase.Price.Validator.valid_price?(slug, "BTC", price_btc),
  #         do: t,
  #         else: Map.put(t, :price_usd, nil)
  #     end)
  #   end)
  # end

  defp export_to_kafka(tickers, cmc_id_to_slugs_mapping) do
    tickers
    |> Enum.flat_map(fn %Ticker{} = ticker ->
      case Map.get(cmc_id_to_slugs_mapping, ticker.slug, []) |> List.wrap() do
        [_ | _] = slugs ->
          price_point = Ticker.to_price_point(ticker) |> PricePoint.sanity_filters()
          Enum.map(slugs, fn slug -> PricePoint.json_kv_tuple(price_point, slug) end)

        _ ->
          []
      end
    end)
    |> Sanbase.KafkaExporter.persist_sync(@prices_exporter)
  rescue
    e ->
      Logger.error(
        "[CMC] Realtime exporter failed to export to Kafka. Reason: #{Exception.message(e)}"
      )
  end

  # Helper functions

  def handle_info(:sync, %{update_interval: update_interval} = state) do
    work()
    Process.send_after(self(), :sync, update_interval * 1000)

    {:noreply, state}
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
    Config.get(:top_projects_to_follow, "25") |> String.to_integer()
  end
end
