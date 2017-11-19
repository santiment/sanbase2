defmodule Sanbase.ExternalServices.Coinmarketcap do
  # # Syncronize data from coinmarketcap.com
  #
  # A GenServer, which updates the data from coinmarketcap on a regular basis.
  # On regular intervals it will fetch the data from coinmarketcap and insert it
  # into a local DB
  use GenServer, restart: :permanent, shutdown: 5_000

  import Ecto.Query

  alias Sanbase.Model.Project
  alias Sanbase.Repo
  alias Sanbase.Prices.{Store, Measurement}
  alias Sanbase.ExternalServices.Coinmarketcap.GraphData
  alias Sanbase.ExternalServices.Coinmarketcap.PricePoint
  alias Sanbase.Notifications.CheckPrices

  @default_update_interval 1000 * 60 * 5 # 5 minutes

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    update_interval = Keyword.get(config(), :update_interval, @default_update_interval)

    if Keyword.get(config(), :sync_enabled, false) do
      Application.fetch_env!(:sanbase, Sanbase.ExternalServices.Coinmarketcap)
      |> Keyword.get(:database)
      |> Instream.Admin.Database.create()
      |> Store.execute()

      GenServer.cast(self(), :sync)

      {:ok, %{update_interval: update_interval}}
    else
      :ignore
    end
  end

  def handle_cast(:sync, %{update_interval: update_interval} = state) do
    Project
    |> where([p], not is_nil(p.coinmarketcap_id) and not is_nil(p.ticker))
    |> Repo.all
    |> Enum.each(&fetch_price_data/1)

    CheckPrices.exec

    Process.send_after(self(), {:"$gen_cast", :sync}, update_interval)

    {:noreply, state}
  end

  def config do
    Application.get_env(:sanbase, __MODULE__)
  end

  defp fetch_price_data(%Project{coinmarketcap_id: coinmarketcap_id, ticker: ticker} = project) do
    GraphData.fetch_prices(
      coinmarketcap_id,
      last_price_datetime(project),
      DateTime.utc_now
    )
    |> Stream.flat_map(fn price_point ->
      [
        convert_to_measurement(price_point, "_usd", "#{ticker}_USD"),
        convert_to_measurement(price_point, "_btc", "#{ticker}_BTC"),
      ]
    end)
    |> Store.import()
  end

  defp convert_to_measurement(%PricePoint{datetime: datetime} = point, suffix, name) do
    %Measurement{
      timestamp: DateTime.to_unix(datetime, :nanosecond),
      fields: price_point_to_fields(point, suffix),
      tags: [source: "coinmarketcap"],
      name: name
    }
  end

  defp price_point_to_fields(%PricePoint{marketcap: marketcap, volume_usd: volume} = point, suffix) do
    %{
      "price": Map.get(point, String.to_atom("price" <> suffix)),
      "volume": volume,
      "marketcap": marketcap
    }
  end

  defp last_price_datetime(%Project{ticker: ticker} = project) do
    usd_datetime = last_price_datetime(ticker <> "_USD", project)
    btc_datetime = last_price_datetime(ticker <> "_BTC", project)

    case DateTime.compare(usd_datetime, btc_datetime) do
      :gt -> btc_datetime
      _ -> usd_datetime
    end
  end

  defp last_price_datetime(pair, %Project{coinmarketcap_id: coinmarketcap_id}) do
    case Store.last_price_datetime(pair) do
      nil ->
        GraphData.fetch_first_price_datetime(coinmarketcap_id)
      datetime ->
        datetime
    end
  end
end
