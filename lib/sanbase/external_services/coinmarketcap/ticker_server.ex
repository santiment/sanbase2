defmodule Sanbase.ExternalServices.Coinmarketcap.TickerFetcher do
  # # Syncronize ticker data from coinmarketcap.com
  #
  # A GenServer, which updates the data from coinmarketcap on a regular basis.
  # On regular intervals it will fetch the data from coinmarketcap and insert it
  # into a local DB
  use GenServer, restart: :permanent, shutdown: 5_000

  alias Sanbase.Model.LatestCoinmarketcapData
  alias Sanbase.Repo
  alias Sanbase.ExternalServices.Coinmarketcap.Ticker

  @default_update_interval 1000 * 60 * 5 # 5 minutes

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    update_interval = Keyword.get(config(), :update_interval, @default_update_interval)

    if Keyword.get(config(), :sync_enabled, false) do
      GenServer.cast(self(), :sync)

      {:ok, %{update_interval: update_interval}}
    else
      :ignore
    end
  end

  def handle_cast(:sync, %{update_interval: update_interval} = state) do
    # Fetch current  marketcap
    Ticker.fetch_data()
    |> Enum.each(&store_ticker/1)

    Process.send_after(self(), {:"$gen_cast", :sync}, update_interval)

    {:noreply, state}
  end

  defp store_ticker(ticker) do
    case Repo.get(LatestCoinmarketcapData, ticker.id) do
      nil  -> %LatestCoinmarketcapData{id: ticker.id}
      entry -> entry
    end
    |> LatestCoinmarketcapData.changeset(
      %{market_cap_usd: ticker.market_cap_usd,
	name: ticker.name,
	price_usd: ticker.price_usd,
	symbol: ticker.symbol,
	update_time: NaiveDateTime.add(~N[1970-01-01 00:00:00],
	  ticker.last_updated)
      })
    |> Repo.insert_or_update!
  end

  def config do
    Application.get_env(:sanbase, __MODULE__)
  end
end
