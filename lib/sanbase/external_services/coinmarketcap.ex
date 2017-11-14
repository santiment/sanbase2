defmodule Sanbase.ExternalServices.Coinmarketcap do
  # # Syncronize data from coinmarketcap.com
  #
  # A GenServer, which updates the data from coinmarketcap on a regular basis.
  # On regular intervals it will fetch the data from coinmarketcap and insert it
  # into a local DB
  use GenServer, restart: :permanent, shutdown: 5_000

  alias Sanbase.Model.Project
  alias Sanbase.Repo
  alias Sanbase.Prices.Store
  alias Sanbase.ExternalServices.Coinmarketcap.GraphData
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
    |> Repo.all
    |> Enum.each(&fetch_price_data/1)

    CheckPrices.exec

    Process.send_after(self(), {:"$gen_cast", :sync}, update_interval)

    {:noreply, state}
  end

  def config do
    Application.get_env(:sanbase, __MODULE__)
  end

  defp fetch_price_data(%Project{coinmarketcap_id: nil}), do: :ok

  defp fetch_price_data(%Project{coinmarketcap_id: coinmarketcap_id} = project) do
    GraphData.fetch_prices(
      coinmarketcap_id,
      last_price_datetime(project),
      DateTime.utc_now
    )
    |> Store.import_price_points(table_name(project), source: "coinmarketcap")
  end

  defp last_price_datetime(project) do
    case Store.last_price_datetime(table_name(project)) do
      nil ->
        fetch_first_price_datetime(project)
      datetime ->
        datetime
    end
  end

  defp fetch_first_price_datetime(%Project{coinmarketcap_id: coinmarketcap_id}) do
    GraphData.fetch_all_time_prices(coinmarketcap_id)
    |> Enum.take(1)
    |> hd
    |> Map.get(:datetime)
  end

  defp table_name(%Project{ticker: ticker}) do
    ticker <> "_USD"
  end
end
