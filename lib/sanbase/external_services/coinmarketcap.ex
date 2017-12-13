defmodule Sanbase.ExternalServices.Coinmarketcap do
  # # Syncronize data from coinmarketcap.com
  #
  # A GenServer, which updates the data from coinmarketcap on a regular basis.
  # On regular intervals it will fetch the data from coinmarketcap and insert it
  # into a local DB
  use GenServer, restart: :permanent, shutdown: 5_000

  import Ecto.Query
  import Sanbase.Utils, only: [parse_config_value: 1]

  require Logger

  alias Sanbase.Model.{Project, Ico}
  alias Sanbase.Repo
  alias Sanbase.Prices.{Store, Measurement}
  alias Sanbase.ExternalServices.Coinmarketcap.{GraphData, PricePoint}
  alias Sanbase.ExternalServices.ProjectInfo
  alias Sanbase.Notifications.CheckPrices

  # 5 minutes
  @default_update_interval 1000 * 60 * 5

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    update_interval = get_config(:update_interval, @default_update_interval)

    if get_config(:sync_enabled, false) do
      Application.fetch_env!(:sanbase, Sanbase.Prices.Store)
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
    query =
      Project
      |> where([p], not is_nil(p.coinmarketcap_id) and not is_nil(p.ticker))

    Task.Supervisor.async_stream_nolink(
      Sanbase.TaskSupervisor,
      Repo.all(query),
      &fetch_project_data/1,
      ordered: false,
      max_concurrency: 5,
      timeout: :infinity
    )
    |> Stream.run()

    Process.send_after(self(), {:"$gen_cast", :sync}, update_interval)

    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.warn("Unknown message received: #{msg}")
    {:noreply, state}
  end

  def config do
    Application.get_env(:sanbase, __MODULE__)
  end

  defp fetch_project_data(project) do
    fetch_project_info(project)
    fetch_price_data(project)
  end

  defp fetch_project_info(%Project{coinmarketcap_id: coinmarketcap_id} = project) do
    if project_info_missing?(project) do
      {:ok, _project} = %ProjectInfo{coinmarketcap_id: coinmarketcap_id}
      |> ProjectInfo.fetch_coinmarketcap_info()
      |> ProjectInfo.fetch_contract_info()
      |> ProjectInfo.update_project(project)
    end
  end

  defp project_info_missing?(%Project{website_link: website_link, github_link: github_link, ticker: ticker, name: name} = project) do
    is_nil(website_link) or is_nil(github_link) or is_nil(ticker) or is_nil(name) or missing_main_contract_address?(project)
  end

  defp missing_main_contract_address?(project) do
    project
    |> Project.initial_ico
    |> case do
      nil -> true
      %Ico{main_contract_address: nil} -> true
      _ -> false
    end
  end

  defp fetch_price_data(%Project{coinmarketcap_id: coinmarketcap_id, ticker: ticker} = project) do
    GraphData.fetch_prices(
      coinmarketcap_id,
      last_price_datetime(project),
      DateTime.utc_now()
    )
    |> Stream.flat_map(fn price_point ->
         [
           convert_to_measurement(price_point, "_usd", "#{ticker}_USD"),
           convert_to_measurement(price_point, "_btc", "#{ticker}_BTC")
         ]
       end)
    |> Store.import()

    CheckPrices.exec(project, "usd")
    CheckPrices.exec(project, "btc")
  end

  defp convert_to_measurement(%PricePoint{datetime: datetime} = point, suffix, name) do
    %Measurement{
      timestamp: DateTime.to_unix(datetime, :nanosecond),
      fields: price_point_to_fields(point, suffix),
      tags: [source: "coinmarketcap"],
      name: name
    }
  end

  defp price_point_to_fields(
         %PricePoint{marketcap: marketcap, volume_usd: volume} = point,
         suffix
       ) do
    %{
      price: Map.get(point, String.to_atom("price" <> suffix)),
      volume: volume,
      marketcap: marketcap
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

  defp get_config(key, default \\ nil) do
    Keyword.get(config(), key, default)
    |> parse_config_value()
  end
end
