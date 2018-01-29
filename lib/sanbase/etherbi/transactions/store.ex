defmodule Sanbase.Etherbi.Transactions.Store do
  @moduledoc ~S"""
    Module with functions for working with transactions influx database
  """
  use Sanbase.Influxdb.Store

  alias Sanbase.Etherbi.Transactions.Store

  def transactions(measurement, from, to, transaction_type) do
    transactions_from_to_query(measurement, from, to, transaction_type)
    |> Store.query()
    |> parse_transactions_time_series()
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

end