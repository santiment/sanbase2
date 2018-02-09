defmodule Sanbase.ExternalServices.Etherscan.Worker do
  # A worker that regularly polls etherscan for tracked addresses and
  # updates the last outgoing transactions in the database

  use GenServer, restart: :permanent, shutdown: 5_000
  require Logger

  require Sanbase.Utils.Config

  import Ecto.Query

  alias Sanbase.Model.LatestEthWalletData
  alias Sanbase.Model.ProjectEthAddress
  alias Sanbase.Repo
  alias Sanbase.InternalServices.Parity
  alias Sanbase.ExternalServices.Etherscan.Requests.{Balance, Tx}
  alias Sanbase.Utils.Config

  alias Sanbase.ExternalServices.Etherscan.Store

  @default_update_interval_ms 1000 * 60 * 5
  @confirmations 10
  @num_18_zeroes 1_000_000_000_000_000_000

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    Logger.info("Starting etherscan polling client")

    if Config.get(:sync_enabled, false) do
      Store.create_db()

      Decimal.set_context(%{Decimal.get_context() | precision: 2})

      update_interval_ms = Config.get(:update_interval, @default_update_interval_ms)

      GenServer.cast(self(), :sync)

      {:ok, %{update_interval_ms: update_interval_ms}}
    else
      :ignore
    end
  end

  def handle_cast(:sync, %{update_interval_ms: update_interval_ms} = state) do
    endblock = Parity.get_latest_block_number!() - @confirmations

    query =
      from(
        eth_addr in ProjectEthAddress,
        inner_join: p in Sanbase.Model.Project,
        on: eth_addr.project_id == p.id,
        where: not is_nil(p.coinmarketcap_id),
        select: %{address: eth_addr.address, coinmarketcap_id: p.coinmarketcap_id}
      )

    Task.Supervisor.async_stream_nolink(
      Sanbase.TaskSupervisor,
      Repo.all(query),
      &fetch_and_store(&1, endblock),
      max_concurrency: 5,
      on_timeout: :kill_task,
      ordered: false,
      timeout: 35_000
    )
    |> Stream.run()

    Process.send_after(self(), {:"$gen_cast", :sync}, update_interval_ms)

    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.warn("Unknown message received: #{msg}")
    {:noreply, state}
  end

  # Private functions

  defp convert_to_eth(wei) do
    Decimal.div(Decimal.new(wei), Decimal.new(@num_18_zeroes))
  end

  defp import_all_transactions_influxdb(transactions, address, id) do
    transactions
    |> Enum.map(&convert_to_measurement(&1, address, id))
    |> Store.import()
  end

  defp import_latest_eth_wallet_data(transactions, address) do
    last_trx =
      transactions
      |> Enum.find(fn tx -> String.downcase(tx.from) == address end)

    changeset = latest_eth_wallet_changeset(last_trx, address)

    get_or_create_entry(address)
    |> LatestEthWalletData.changeset(changeset)
    |> Repo.insert_or_update!()
  end

  defp latest_eth_wallet_changeset(last_trx, address) do
    changeset = %{
      update_time: DateTime.utc_now(),
      balance: convert_to_eth(Balance.get(address).result)
    }

    case last_trx do
      %Tx{timeStamp: ts, value: value} ->
        Map.merge(changeset, %{
          last_outgoing: DateTime.from_unix!(ts),
          tx_out: convert_to_eth(value)
        })

      nil ->
        changeset
    end
  end

  defp fetch_all_transactions(address, measurement_name, endblock) do
    last_block_with_data = Store.last_block_number!(address) || 0

    case Tx.get_all_transactions(address, last_block_with_data, endblock) do
      {:ok, list} ->
        list

      {:error, error} ->
        Logger.warn(
          "Cannot fetch transactions for #{measurement_name}'s wallet: #{address}. Reason: #{
            inspect(error)
          }"
        )

        []
    end
  end

  defp fetch_and_store(%{address: address, coinmarketcap_id: id}, endblock) do
    transactions = fetch_all_transactions(address, id, endblock)
    address = address |> String.downcase()

    filtered_transactions =
      transactions
      |> Enum.reject(fn %Tx{isError: error, txreceipt_status: status, value: value} ->
        error == "1" || status == "0" || value == "0"
      end)

    import_all_transactions_influxdb(filtered_transactions, address, id)

    import_latest_eth_wallet_data(filtered_transactions, address)

    import_last_block_number(address, List.last(transactions))
  end

  defp import_last_block_number(address, %Tx{blockNumber: bn}) do
    Store.import_last_block_number(address, bn)
  end

  defp get_or_create_entry(address) do
    case Repo.get_by(LatestEthWalletData, address: address) do
      nil -> %LatestEthWalletData{address: address}
      entry -> entry
    end
  end

  defp convert_to_measurement(
         %Tx{
           timeStamp: ts,
           from: from,
           to: to,
           value: value,
           blockNumber: bn,
           transactionIndex: trx_index
         },
         address,
         measurement_name
       ) do
    from = from |> String.downcase()
    to = to |> String.downcase()

    transaction_type =
      if to == address do
        "in"
      else
        "out"
      end

    %Sanbase.Influxdb.Measurement{
      timestamp: ts * 1_000_000_000,
      fields: %{
        trx_value: (value |> String.to_integer()) / @num_18_zeroes,
        block_number: bn |> String.to_integer(),
        transaction_index: trx_index |> String.to_integer(),
        from_addr: from,
        to_addr: to
      },
      tags: [transaction_type: transaction_type],
      name: measurement_name
    }
  end
end
