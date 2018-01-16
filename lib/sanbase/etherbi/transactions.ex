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

  @default_update_interval 5 * 60_000

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    if Config.get(:sync_enabled, false) do
      Store.create_db()
      update_interval_ms = Config.get(:update_interval, @default_update_interval)

      GenServer.cast(self(), :sync)
      {:ok, %{update_interval_ms: update_interval_ms}}
    else
      :ignore
    end
  end

  def handle_cast(:sync, %{update_interval_ms: update_interval_ms} = state) do
    exchange_wallets_addrs = Repo.all(from(addr in ExchangeEthAddress, select: addr.address))

    Task.Supervisor.async_stream_nolink(
      Sanbase.TaskSupervisor,
      exchange_wallets_addrs,
      &fetch_and_store/1,
      ordered: false,
      max_concurency: System.schedulers_online() * 2,
      timeout: 1000 * 60
    )
    |> Stream.run()

    Process.send_after(self(), {:"$gen_cast", :sync}, update_interval_ms)
    {:noreply, state}
  end

  defp fetch_and_store(address) do
    last_datetime = Store.last_datetime(address) || DateTime.from_unix!(0, :seconds)
    now_datetime = DateTime.utc_now()

    transactions_in = FundsMovement.transactions_in(last_datetime, now_datetime, [address])

    convert_to_measurement(transactions_in, address, "in")
    |> Store.import()

    transactions_out = FundsMovement.transactions_out(last_datetime, now_datetime, [address])

    convert_to_measurement(transactions_out, address, "out")
    |> Store.import()
  end

  # Influxdb has 64 bytes integer which is not always sufficient for the volume
  defp convert_to_measurement(
         transactions_data,
         measurement_name,
         transaction_type
       ) do
    transactions_data
    |> Enum.map(fn {datetime, volume, _address, token} ->
      %Measurement{
        timestamp: datetime |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: volume |> Integer.to_string(), token: token},
        tags: [transaction_type: transaction_type],
        name: measurement_name
      }
    end)
  end
end