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
  @spec import_last_address_time(String.t(), atom, %DateTime{}) :: :ok | no_return()
  def import_last_address_time(_, _, nil), do: :ok

  def import_last_address_time(address, trx_type, last_datetime) do
    address_trx_type = "#{address}_#{trx_type}"
    Store.delete_by_tag(@last_address_measurement, "address_trx_type", address_trx_type)

    %Sanbase.Influxdb.Measurement{
      timestamp: DateTime.utc_now() |> DateTime.to_unix(:nanoseconds),
      fields: %{last_datetime: last_datetime |> DateTime.to_unix()},
      tags: [address_trx_type: address_trx_type],
      name: @last_address_measurement
    }
    |> Store.import()
  end

  @doc ~S"""
    Get a list of fund flows in and out of exchange. The query returns a tuple `{:ok, list}` or
    `{:error, reason}`. `list` is list of`{:datetime, amount}`.
    Positive `amount` indicates that more funds have flown into
    than out of exchanges.
    Negative `amount` indicates that more funds have flown out
    than in of exchanges.
  """
  @spec transactions_in_out_difference(String.t(), %DateTime{}, %DateTime{}, String.t()) ::
          {:ok, list()} | {:error, String.t()}
  def transactions_in_out_difference(measurement, from, to, interval) do
    transactions_in_out_difference_query(measurement, from, to, interval)
    |> Store.query()
    |> parse_in_out_diff_time_series()
  end

  @doc ~S"""
    Get a list of fund flows in and out of exchange. The query returns a tuple `list` or
    raises an error. `list` is list of`{:datetime, amount}`.
    Positive `amount` indicates that more funds have flown into
    than out of exchanges.
    Negative `amount` indicates that more funds have flown out
    than in of exchanges.
  """
  @spec transactions_in_out_difference!(String.t(), %DateTime{}, %DateTime{}, String.t()) ::
          list() | no_return()
  def transactions_in_out_difference!(measurement, from, to, interval) do
    case transactions_in_out_difference(measurement, from, to, interval) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end

  # Private functions

  defp transactions_in_out_difference_query(measurement, from, to, interval) do
    ~s/SELECT (SUM(incoming_exchange_funds) - SUM(outgoing_exchange_funds)) as funds_flow
    FROM "#{measurement}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}
    GROUP BY time(#{interval}) fill(0)/
  end

  defp parse_transactions_time_series(%{results: [%{error: error}]}) do
    {:error, error}
  end

  defp parse_in_out_diff_time_series(%{
         results: [
           %{
             series: [
               %{
                 values: funds_flow_list
               }
             ]
           }
         ]
       }) do
    result =
      funds_flow_list
      |> Enum.map(fn [iso8601_datetime, funds_flow] ->
        {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)
        {datetime, funds_flow}
      end)

    {:ok, result}
  end

  defp parse_in_out_diff_time_series(_) do
    {:ok, []}
  end
end
