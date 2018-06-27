defmodule Sanbase.ExternalServices.Coinmarketcap.TickerFetcher2 do
  @moduledoc ~s"""
    A GenServer, which updates the data from coinmarketcap on a regular basis.

    Fetches only the current info and no historical data.
    On predefined intervals it will fetch the data from coinmarketcap and insert it
    into a local DB
  """
  use GenServer, restart: :permanent, shutdown: 5_000

  require Sanbase.Utils.Config

  alias Sanbase.Model.LatestCoinmarketcapData
  alias Sanbase.Model.Project
  alias Sanbase.Repo
  # TODO: Change after switching over to only this cmc
  alias Sanbase.ExternalServices.Coinmarketcap.Ticker2, as: Ticker
  alias Sanbase.Utils.Config
  alias Sanbase.Prices.Store

  # 5 minutes
  @default_update_interval 1000 * 60 * 5

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    if Config.get(:sync_enabled, false) do
      Store.create_db()

      Process.send(self(), :sync, [:noconnect])

      update_interval = Config.get(:update_interval, @default_update_interval)
      {:ok, %{update_interval: update_interval}}
    else
      :ignore
    end
  end

  def work() do
    # Fetch current coinmarketcap data for many tickers
    {:ok, tickers} = Ticker.fetch_data()

    # Create a project if it's a new one in the top projects and we don't have it
    tickers
    |> Enum.take(top_projects_to_follow())
    |> Enum.each(&insert_or_create_project/1)

    # Store the data in LatestCoinmarketcapData in postgres
    tickers
    |> Enum.each(&store_latest_coinmarketcap_data/1)

    # Store the data in Influxdb
    tickers
    |> Enum.map(&Ticker.convert_for_importing/1)
    |> Store.import()
  end

  # Helper functions

  def handle_info(:sync, %{update_interval: update_interval} = state) do
    work()
    Process.send_after(self(), :sync, update_interval)

    {:noreply, state}
  end

  defp get_or_create_latest_coinmarketcap_data(coinmarketcap_id) do
    case Repo.get_by(LatestCoinmarketcapData, coinmarketcap_id: coinmarketcap_id) do
      nil ->
        %LatestCoinmarketcapData{coinmarketcap_id: coinmarketcap_id}

      entry ->
        entry
    end
  end

  defp store_latest_coinmarketcap_data(%Ticker{id: coinmarketcap_id} = ticker) do
    coinmarketcap_id
    |> get_or_create_latest_coinmarketcap_data()
    |> LatestCoinmarketcapData.changeset(%{
      market_cap_usd: ticker.market_cap_usd,
      name: ticker.name,
      price_usd: ticker.price_usd,
      price_btc: ticker.price_btc,
      rank: ticker.rank,
      volume_usd: ticker."24h_volume_usd",
      available_supply: ticker.available_supply,
      total_supply: ticker.total_supply,
      symbol: ticker.symbol,
      percent_change_1h: ticker.percent_change_1h,
      percent_change_24h: ticker.percent_change_24h,
      percent_change_7d: ticker.percent_change_7d,
      update_time: DateTime.from_unix!(ticker.last_updated)
    })
    |> Repo.insert_or_update!()
  end

  defp insert_or_create_project(%Ticker{id: coinmarketcap_id, name: name, symbol: ticker}) do
    find_or_init_project(%Project{name: name, coinmarketcap_id: coinmarketcap_id, ticker: ticker})
    |> Repo.insert_or_update!()
  end

  defp find_or_init_project(%Project{coinmarketcap_id: coinmarketcap_id} = project) do
    case Repo.get_by(Project, coinmarketcap_id: coinmarketcap_id) do
      nil ->
        Project.changeset(project)

      existing_project ->
        Project.changeset(existing_project, %{
          coinmarketcap_id: coinmarketcap_id,
          ticker: project.ticker
        })
    end
  end

  defp top_projects_to_follow() do
    Config.get(:top_projects_to_follow, "25") |> String.to_integer()
  end
end
