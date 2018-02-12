defmodule Sanbase.Etherbi.Transactions.Store do
  @moduledoc ~S"""
    Module with functions for working with transactions influx database
  """
  use Sanbase.Influxdb.Store

  alias Sanbase.Etherbi.Transactions.Store

  @last_address_measurement "_sanbase-internal-last-address-measurement"

  @doc ~s"""
    Updates the point for `address` in the special measurement used for saving
    the last queried timestamp for a given address
  """
  @spec import_last_address_time(String.t(), String.t(), %DateTime{}) :: :ok | no_return()
  def import_last_address_time(_, _, nil), do: :ok

  def import_last_address_time(address, trx_type, last_datetime) do
    Store.delete_by_tag(@last_address_measurement, "address", address)

    %Sanbase.Influxdb.Measurement{
      timestamp: DateTime.utc_now() |> DateTime.to_unix(:nanoseconds),
      fields: %{last_datetime: last_datetime |> DateTime.to_unix(:nanoseconds)},
      tags: [address: address, transaction_type: trx_type],
      name: @last_address_measurement
    }
    |> Store.import()
  end

  @doc ~s"""
    Returns the last datetime that was quried for that particular address.
    Returns `{:ok, datetime}` on successs, `{:error, reason}` otherwise
  """
  @spec last_address_datetime(String.t(), String.t()) ::
          {:ok, %DateTime{}} | {:ok, nil} | {:error, String.t()}
  def last_address_datetime(address, trx_type) do
    select_last_address_datetime(address, trx_type)
    |> Store.query()
    |> parse_last_address_datetime()
  end

  @doc ~S"""
    Get all in and/or out transactions that happened with a given address.
    Returns a tuple `{:ok, result}` on success, `{:error, error}` otherwise
  """
  @spec transactions(binary(), %DateTime{}, %DateTime{}, binary()) ::
          {:ok, list()} | {:error, binary()}
  def transactions(measurement, from, to, transaction_type) do
    transactions_from_to_query(measurement, from, to, transaction_type)
    |> Store.query()
    |> parse_transactions_time_series()
  end

  @doc ~S"""
    Get all in and/or out transactions that happened with a given address. Retunrs `result`
    on success, raises and error otherwise
  """
  @spec transactions!(binary(), %DateTime{}, %DateTime{}, binary()) :: list() | no_return()
  def transactions!(measurement, from, to, transaction_type) do
    case transactions(measurement, from, to, transaction_type) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end

  # Private functions

  defp select_last_address_datetime(address, trx_type) do
    ~s/SELECT LAST(address)
    FROM "#{@last_address_measurement}"
    WHERE address='#{address}'
    AND transaction_type='#{trx_type}/
  end

  defp transactions_from_to_query(measurement, from, to, "all") do
    ~s/SELECT volume, address
    FROM "#{measurement}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
  end

  defp transactions_from_to_query(measurement, from, to, transaction_type) do
    ~s/SELECT volume, address
    FROM "#{measurement}"
    WHERE transaction_type = '#{transaction_type}'
    AND time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
  end

  defp parse_transactions_time_series(%{error: error}) do
    {:error, error}
  end

  defp parse_transactions_time_series(%{results: [%{error: error}]}) do
    {:error, error}
  end

  defp parse_transactions_time_series(%{
         results: [
           %{
             series: [
               %{
                 values: transactions
               }
             ]
           }
         ]
       }) do
    result =
      transactions
      |> Enum.map(fn [iso8601_datetime, volume, address] ->
        {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)
        {datetime, volume, address}
      end)

    {:ok, result}
  end

  defp parse_transactions_time_series(_) do
    {:ok, []}
  end

  defp parse_last_address_datetime(%{results: [%{error: error}]}) do
    {:error, error}
  end

  defp parse_last_address_datetime(%{
         results: [
           %{
             series: [
               %{
                 values: last_address
               }
             ]
           }
         ]
       }) do
    [[iso8601_datetime, _]] = last_address
    {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)
    {:ok, datetime}
  end

  defp parse_last_address_datetime(_), do: {:ok, nil}
end
