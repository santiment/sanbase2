defmodule Sanbase.Etherbi.Transactions do
  use GenServer

  require Sanbase.Utils.Config

  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Utils.Config
  alias Sanbase.Etherbi.Store
  alias Sanbase.Etherbi.FundsMovement
  alias Sanbase.Model.ExchangeEthAddress
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Model.Project

  @default_update_interval 5 * 60_000

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    if Config.get(:sync_enabled, false) do
      Store.create_db()
      update_interval_ms = Config.get(:update_interval, @default_update_interval)

      GenServer.cast(self(), :sync)
      token_decimals = build_token_decimals_map()
      {:ok, %{update_interval_ms: update_interval_ms, token_decimals: token_decimals}}
    else
      :ignore
    end
  end

  def handle_cast(
        :sync,
        %{update_interval_ms: update_interval_ms, token_decimals: token_decimals} = state
      ) do
    exchange_wallets_addrs = Repo.all(from(addr in ExchangeEthAddress, select: addr.address))

    Task.Supervisor.async_stream_nolink(
      Sanbase.TaskSupervisor,
      exchange_wallets_addrs,
      &fetch_and_store(&1, token_decimals),
      max_concurency: 1,
      timeout: 1000 * 60 * 2
    )
    |> Stream.run()

    Process.send_after(self(), {:"$gen_cast", :sync}, update_interval_ms)
    {:noreply, state}
  end

  defp fetch_and_store(address, token_decimals) do
    last_datetime = Store.last_datetime(address) || DateTime.from_unix!(0, :seconds)
    now_datetime = DateTime.utc_now()

    {:ok, transactions_in} = FundsMovement.transactions_in([address], last_datetime, now_datetime)
    convert_to_measurement(transactions_in, address, "in", token_decimals)
    |> Store.import()

    {:ok, transactions_out} = FundsMovement.transactions_out([address], last_datetime, now_datetime)
    convert_to_measurement(transactions_out, address, "out", token_decimals)
    |> Store.import()
  end

  defp build_token_decimals_map() do
    query =
      from(
        p in Project,
        where: not is_nil(p.token_decimals),
        select: %{ticker: p.ticker, token_decimals: p.token_decimals}
      )

    Repo.all(query)
    |> Enum.map(fn %{ticker: ticker, token_decimals: token_decimals} ->
      {ticker, token_decimals}
    end)
    |> Map.new()
  end

  # Influxdb has 64 bytes integer which is not always sufficient for the volume
  defp convert_to_measurement(
         transactions_data,
         measurement_name,
         transaction_type,
         token_decimals
       ) do
    transactions_data
    |> Enum.map(fn {datetime, volume, _address, token} ->
      %Measurement{
        timestamp: datetime |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: volume / Map.get(token_decimals, token, 1)},
        tags: [transaction_type: transaction_type],
        name: measurement_name
      }
    end)
  end
end