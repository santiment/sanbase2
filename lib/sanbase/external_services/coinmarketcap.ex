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
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Prices.Store
  alias Sanbase.ExternalServices.ProjectInfo
  alias Sanbase.ExternalServices.Coinmarketcap.GraphData
  alias Sanbase.ExternalServices.Coinmarketcap.PricePoint
  alias Sanbase.Notifications.CheckPrices
  alias Sanbase.Notifications.PriceVolumeDiff
  alias Sanbase.Utils.Config

  # 5 minutes
  @default_update_interval 1000 * 60 * 5

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    if Config.get(:sync_enabled, false) do
      Store.create_db()

      GenServer.cast(self(), :sync)

      update_interval = Config.get(:update_interval, @default_update_interval)
      {:ok, %{update_interval: update_interval}}
    else
      :ignore
    end
  end

  def handle_cast(:sync, %{update_interval: update_interval} = state) do
    projects =
      Project
      |> where([p], not is_nil(p.coinmarketcap_id) and not is_nil(p.ticker))
      |> Repo.all()

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
      &fetch_and_process_price_data/1,
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
      ProjectInfo.from_project(project)
      |> ProjectInfo.fetch_coinmarketcap_info()
      |> case do
        {:ok, project_info_with_coinmarketcap_info} ->
          project_info_with_coinmarketcap_info
          |> ProjectInfo.fetch_etherscan_token_summary()
          |> ProjectInfo.fetch_contract_info()
          |> ProjectInfo.update_project(project)

        _ ->
          nil
      end
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
    !website_link or !github_link or !ticker or !name or missing_main_contract_address?(project) or
      !token_decimals
  end

  defp missing_main_contract_address?(project) do
    project
    |> Project.initial_ico()
    |> case do
      nil -> true
      %Ico{} = ico -> missing_ico_info?(ico)
      _ -> false
    end
  end

  defp missing_ico_info?(%Ico{
         main_contract_address: main_contract_address,
         contract_abi: contract_abi,
         contract_block_number: contract_block_number
       }) do
    !main_contract_address or !contract_abi or !contract_block_number
  end

  defp fetch_and_process_price_data(%Project{coinmarketcap_id: coinmarketcap_id} = project) do
    last_price_datetime = last_price_datetime(project)

    prices = fetch_prices(project, last_price_datetime)

    prices |> Store.import()

    last_price_datetime_updated =
      prices
      |> Enum.max_by(&Measurement.get_timestamp/1)
      |> Measurement.get_datetime()

    Store.update_last_history_datetime_cmc(coinmarketcap_id, last_price_datetime_updated)

    process_notifications(project)
  end

  defp fetch_prices(
         %Project{coinmarketcap_id: coinmarketcap_id, ticker: ticker},
         last_price_datetime
       ) do
    GraphData.fetch_prices(
      coinmarketcap_id,
      last_price_datetime,
      DateTime.utc_now()
    )
    |> Stream.flat_map(fn price_point ->
      [
        PricePoint.convert_to_measurement(price_point, "USD", ticker),
        PricePoint.convert_to_measurement(price_point, "BTC", ticker)
      ]
    end)
  end

  defp process_notifications(%Project{} = project) do
    CheckPrices.exec(project, "usd")
    CheckPrices.exec(project, "btc")

    PriceVolumeDiff.exec(project, "usd")
  end

  defp last_price_datetime(%Project{coinmarketcap_id: coinmarketcap_id}) do
    case Store.last_history_datetime_cmc!(coinmarketcap_id) do
      nil ->
        GraphData.fetch_first_price_datetime(coinmarketcap_id)

      datetime ->
        datetime
    end
  end
end
