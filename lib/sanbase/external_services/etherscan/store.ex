defmodule Sanbase.ExternalServices.Etherscan.Store do
  @moduledoc ~S"""
    A module for storing and fetching transactions data from a time series data store
  """

  use Sanbase.Influxdb.Store

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.ExternalServices.Etherscan.Store

  def last_block_number(measurement) do
    select_last_block_number(measurement)
    |> Store.query()
    |> parse_last_block_number()
  end

  def last_block_number!(measurement) do
    case last_block_number(measurement) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end

  def transactions(measurement, from, to) do
    select_from_to_query(measurement, from, to)
    |> Store.query()
    |> parse_transactions_time_series()
  end

  # Private functions

  defp select_last_block_number(measurement) do
    ~s/SELECT LAST(block_number) from "#{measurement}"/
  end

  defp select_from_to_query(measurement, from, to) do
    ~s/SELECT time, trx_value, from_addr, to_addr
    FROM "#{measurement}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
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
      |> Enum.map(fn [iso8601_datetime, trx_value, from_addr, to_addr] ->
        {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)
        {datetime, trx_value, from_addr, to_addr}
      end)

    {:ok, result}
  end

  defp parse_transactions_time_series(_), do: {:ok, []}

  defp parse_last_block_number(%{results: [%{error: error}]}) do
    {:error, error}
  end

  defp parse_last_block_number(%{
         results: [
           %{
             series: [
               %{
                 values: block_number
               }
             ]
           }
         ]
       }) do
    block_number
    |> Enum.map(fn [_iso8601_datetime, block_number] ->
      {:ok, block_number}
    end)
  end

  defp parse_last_block_number(_), do: {:ok, nil}
end
