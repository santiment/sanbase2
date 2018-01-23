defmodule Sanbase.ExternalServices.Coinmarketcap do
  @moduledoc """
  # Syncronize data from coinmarketcap.com

  A GenServer, which updates the data from coinmarketcap on a regular basis.
  On regular intervals it will fetch the data from coinmarketcap and insert it
  into a local DB
  """
  use GenServer, restart: :permanent, shutdown: 5_000

  import Ecto.Query

  require Sanbase.Utils.Config
  require Logger

  alias Sanbase.Model.{Project, Ico}
  alias Sanbase.Repo
  alias Sanbase.Prices.Store
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Prices.Store
  alias Sanbase.ExternalServices.ProjectInfo
  alias Sanbase.ExternalServices.Coinmarketcap.GraphData
  alias Sanbase.ExternalServices.Coinmarketcap.PricePoint
  alias Sanbase.Notifications.CheckPrices
  alias Sanbase.Utils.Config

  # 5 minutes
  @default_update_interval 1000 * 60 * 5

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    update_interval = Config.get(:update_interval, @default_update_interval)

    if Config.get(:sync_enabled, false) do
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
    projects =
      Project
      |> where([p], not is_nil(p.coinmarketcap_id) and not is_nil(p.ticker))
      |> Repo.all

    Task.Supervisor.async_stream_nolink(
      Sanbase.TaskSupervisor,
      projects,
      &fetch_project_info/1,
      ordered: false,
      max_concurrency: 5,
      timeout: 60_000
    )
    |> Stream.run()

    Task.Supervisor.async_stream_nolink(
      Sanbase.TaskSupervisor,
      projects,
      &fetch_price_data/1,
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

  defp fetch_project_info(project) do
    if project_info_missing?(project) do
      {:ok, _project} = ProjectInfo.from_project(project)
      |> ProjectInfo.fetch_coinmarketcap_info()
      |> ProjectInfo.fetch_etherscan_token_summary()
      |> ProjectInfo.fetch_contract_info()
      |> ProjectInfo.update_project(project)
    end
  end

  defp project_info_missing?(
       %Project{
         website_link: website_link,
         github_link: github_link,
         ticker: ticker,
         name: name,
         token_decimals: token_decimals
       } = project
     ) do
    !website_link or !github_link or !ticker or !name
    or missing_main_contract_address?(project) or !token_decimals
  end

  defp missing_main_contract_address?(project) do
    project
    |> Project.initial_ico
    |> case do
      nil -> true
      %Ico{} = ico -> missing_ico_info?(ico)
      _ -> false
    end
  end

  defp missing_ico_info?(%Ico{main_contract_address: main_contract_address, contract_abi: contract_abi, contract_block_number: contract_block_number}) do
    !main_contract_address or !contract_abi or !contract_block_number
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
end
