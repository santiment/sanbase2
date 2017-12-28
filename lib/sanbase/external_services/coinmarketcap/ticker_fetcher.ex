defmodule Sanbase.ExternalServices.Coinmarketcap.TickerFetcher do
  # # Syncronize ticker data from coinmarketcap.com
  #
  # A GenServer, which updates the data from coinmarketcap on a regular basis.
  # On regular intervals it will fetch the data from coinmarketcap and insert it
  # into a local DB
  use GenServer, restart: :permanent, shutdown: 5_000

  import Sanbase.Utils, only: [parse_config_value: 1]

  alias Sanbase.Model.LatestCoinmarketcapData
  alias Sanbase.Model.Project
  alias Sanbase.Repo
  alias Sanbase.ExternalServices.Coinmarketcap.Ticker

  @default_update_interval 1000 * 60 * 5 # 5 minutes
  @top_projects_to_follow 25

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    update_interval = get_config(:update_interval, @default_update_interval)

    if get_config(:sync_enabled, false) do
      GenServer.cast(self(), :sync)

      {:ok, %{update_interval: update_interval}}
    else
      :ignore
    end
  end

  def handle_cast(:sync, %{update_interval: update_interval} = state) do
    # Fetch current  marketcap
    tickers = Ticker.fetch_data()

    tickers
    |> Enum.each(&store_ticker/1)

    tickers
    |> Enum.take(@top_projects_to_follow)
    |> Enum.each(&insert_or_create_project/1)

    Process.send_after(self(), {:"$gen_cast", :sync}, update_interval)

    {:noreply, state}
  end

  defp get_or_create_ticker(coinmarketcap_id) do
    case Repo.get_by(LatestCoinmarketcapData, coinmarketcap_id: coinmarketcap_id) do
      nil  -> %LatestCoinmarketcapData{coinmarketcap_id: coinmarketcap_id}
      entry -> entry
    end
  end

  defp store_ticker(ticker) do
    ticker.id
    |> get_or_create_ticker()
    |> LatestCoinmarketcapData.changeset(
      %{
        market_cap_usd: ticker.market_cap_usd,
	name: ticker.name,
	price_usd: ticker.price_usd,
  rank: ticker.rank,
  volume_24h_usd: ticker.'24h_volume_usd',
	symbol: ticker.symbol,
	update_time: DateTime.from_unix!(ticker.last_updated)
      })
    |> Repo.insert_or_update!
  end

  defp insert_or_create_project(%Ticker{id: coinmarketcap_id, name: name, symbol: ticker}) do
    find_or_init_project(%Project{name: name, coinmarketcap_id: coinmarketcap_id, ticker: ticker})
    |> Repo.insert_or_update!
  end

  defp find_or_init_project(%Project{coinmarketcap_id: coinmarketcap_id} = project) do
    case Repo.get_by(Project, coinmarketcap_id: coinmarketcap_id) do
      nil -> Project.changeset(project)
      existing_project -> Project.changeset(existing_project, %{coinmarketcap_id: coinmarketcap_id, ticker: project.ticker})
    end
  end

  def config do
    Application.get_env(:sanbase, __MODULE__)
  end

  defp get_config(key, default \\ nil) do
    Keyword.get(config(), key, default)
    |> parse_config_value()
  end
end
