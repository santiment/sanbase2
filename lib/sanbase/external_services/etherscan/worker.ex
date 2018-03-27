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
  alias Sanbase.ExternalServices.Etherscan.Requests.{Balance, Tx, InternalTx}
  alias Sanbase.Utils.Config

  alias Sanbase.ExternalServices.Etherscan.Store

  @default_update_interval_ms 1000 * 60 * 5
  @confirmations 10
  @num_18_zeroes 1_000_000_000_000_000_000
  @tx Mockery.of("Sanbase.ExternalServices.Etherscan.Requests.Tx")
  @internal_tx Mockery.of("Sanbase.ExternalServices.Etherscan.Requests.InternalTx")

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
        # That's the name of the measurement
        where: not is_nil(p.ticker),
        select: %{address: eth_addr.address, ticker: p.ticker}
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

  def fetch_and_store(%{address: address, ticker: ticker}, endblock) do
    address = address |> String.downcase()

    transactions =
      fetch_transactions(address, ticker, endblock)
      |> Enum.reverse()

    store_transactions(transactions, address, ticker)

    internal_transactions =
      fetch_internal_transactions(address, ticker, endblock)
      |> Enum.reverse()

    store_transactions(internal_transactions, address, ticker)

    process_last_out_transactions(address, transactions, internal_transactions)
  end

  def handle_info(msg, state) do
    Logger.warn("Unknown message received: #{msg}")
    {:noreply, state}
  end

  # Private functions

  defp convert_to_eth(wei) do
    Decimal.div(Decimal.new(wei), Decimal.new(@num_18_zeroes))
  end

  defp import_latest_eth_wallet_data(last_trx, address) do
    case Balance.get_balance(address) do
      {:ok, balance} ->
        changeset =
          last_trx
          |> get_last_trx_changeset
          |> build_latest_eth_wallet_changeset(balance)

        address
        |> get_or_create_entry()
        |> LatestEthWalletData.changeset(changeset)
        |> Repo.insert_or_update!()

      {:error, _error} ->
        nil
    end
  end

  defp build_latest_eth_wallet_changeset(last_trx_changeset, balance) do
    Map.merge(
      %{
        update_time: DateTime.utc_now(),
        balance: convert_to_eth(balance.result)
      },
      last_trx_changeset
    )
  end

  defp get_last_trx_changeset(nil), do: %{}

  defp get_last_trx_changeset(%Tx{timeStamp: ts, value: value}) do
    %{
      last_outgoing: DateTime.from_unix!(ts),
      tx_out: convert_to_eth(value)
    }
  end

  defp get_last_trx_changeset(%InternalTx{timeStamp: ts, value: value}) do
    %{
      last_outgoing: DateTime.from_unix!(ts),
      tx_out: convert_to_eth(value)
    }
  end

  defp fetch_internal_transactions(address, measurement_name, endblock) do
    last_block_with_data = Store.last_block_number!(address <> "_in") || 0

    case @internal_tx.get(address, last_block_with_data, endblock) do
      {:ok, list} ->
        list

      {:error, error} ->
        Logger.warn(
          "Cannot fetch internal transactions for #{measurement_name}'s wallet: #{address}. Reason: #{
            inspect(error)
          }"
        )

        []
    end
  end

  defp fetch_transactions(address, measurement_name, endblock) do
    last_block_with_data = Store.last_block_number!(address) || 0

    case @tx.get(address, last_block_with_data, endblock) do
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

  defp store_transactions(transactions, address, ticker) do
    transactions
    |> Enum.reject(&reject_transaction?/1)
    |> Enum.map(&convert_to_measurement(&1, address, ticker))
    |> Store.import()

    last_trx = List.first(transactions)
    import_last_block_number(address, last_trx)
  end

  defp reject_transaction?(%Tx{isError: error, txreceipt_status: status, value: value}) do
    error == "1" || status == "0" || value == "0"
  end

  defp reject_transaction?(%InternalTx{isError: error, errCode: err_code, value: value}) do
    error == "1" || err_code != "" || value == "0"
  end

  defp reject_transaction?(_), do: true

  defp import_last_block_number(_address, nil), do: :ok

  defp import_last_block_number(address, %InternalTx{blockNumber: bn}) do
    Store.import_last_block_number(address <> "_in", bn)
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

  defp process_last_out_transactions(address, transactions, internal_transactions) do
    last_out_trx =
      transactions
      |> Enum.find(fn x -> String.downcase(x.from) == address end)

    last_internal_out_trx =
      internal_transactions
      |> Enum.find(fn x -> String.downcase(x.from) == address end)

    # The transaction could be `nil`
    if timestamp_or_zero(last_out_trx) > timestamp_or_zero(last_internal_out_trx) do
      import_latest_eth_wallet_data(last_out_trx, address)
    else
      import_latest_eth_wallet_data(last_internal_out_trx, address)
    end
  end

  defp timestamp_or_zero(nil), do: 0
  defp timestamp_or_zero(%Tx{timeStamp: ts}), do: ts
  defp timestamp_or_zero(%InternalTx{timeStamp: ts}), do: ts

  # Convert a transaction to measurement
  defp convert_to_measurement(
         tx,
         address,
         measurement_name
       ) do
    # Extract the fields from either %Tx{} or %InternalTx{}
    %{
      hash: hash,
      timeStamp: ts,
      from: from,
      to: to,
      value: value,
      blockNumber: bn
    } = Map.from_struct(tx)

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
        trx_hash: hash,
        trx_value: (value |> String.to_integer()) / @num_18_zeroes,
        block_number: bn |> String.to_integer(),
        from_addr: from,
        to_addr: to
      },
      tags: [transaction_type: transaction_type],
      name: measurement_name
    }
  end
end
