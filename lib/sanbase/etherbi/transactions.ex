defmodule Sanbase.Etherbi.Transactions do
  @moduledoc ~S"""
    This module is a GenServer that periodically sends requests to etherbi API.
    In and out transactions are fetched and saved in a time series database for
    easier aggregation and querying.
  """

  @default_update_interval 1000 * 60 * 5
  use Sanbase.Etherbi.EtherbiGenServer

  import Ecto.Query

  alias Sanbase.Etherbi.Utils
  alias Sanbase.Etherbi.Transactions.{Store, Fetcher}

  def work() do
    # Precalculate the number by which we have to divide, that is pow(10, decimal_places)
    token_decimals = Utils.build_token_decimals_map()

    exchange_wallets_addrs =
      Sanbase.Repo.all(from(addr in Sanbase.Model.ExchangeEthAddress, select: addr.address))

    Task.Supervisor.async_stream_nolink(
      Sanbase.TaskSupervisor,
      exchange_wallets_addrs,
      &fetch_and_store_in(&1, token_decimals),
      max_concurency: 1,
      timeout: 165_000
    )
    |> Stream.run()

    Task.Supervisor.async_stream_nolink(
      Sanbase.TaskSupervisor,
      exchange_wallets_addrs,
      &fetch_and_store_out(&1, token_decimals),
      max_concurency: 1,
      timeout: 165_000
    )
    |> Stream.run()
  end

  def fetch_and_store_in(address, token_decimals) do
    with {:ok, transactions_in} <- Fetcher.transactions_in(address) do
      convert_to_measurement(transactions_in, "in", token_decimals)
      |> Store.import()
    else
      {:error, reason} ->
        Logger.warn("Could not fetch and store in transactions for #{address}: #{reason}")
    end
  end

  def fetch_and_store_out(address, token_decimals) do
    with {:ok, transactions_out} <- Fetcher.transactions_out(address) do
      convert_to_measurement(transactions_out, "out", token_decimals)
      |> Store.import()
    else
      {:error, reason} ->
        Logger.warn("Could not fetch and store out transactions for #{address}: #{reason}")
    end
  end

  # Private functions

  # Better return no information than wrong information. If we have no data for the
  # number of decimal places `nil` is written instead and it gets filtered by the Store.import()
  defp convert_to_measurement(
         transactions_data,
         transaction_type,
         token_decimals
       ) do
    transactions_data
    |> Enum.map(fn {datetime, volume, address, token} ->
      %Sanbase.Influxdb.Measurement{
        timestamp: datetime |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: volume / Map.get(token_decimals, token)},
        tags: [transaction_type: transaction_type, address: address],
        name: token
      }
    end)
  end
end