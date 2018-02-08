defmodule Sanbase.ExternalServices.Etherscan.Store do
  @moduledoc ~S"""
    A module for storing and fetching transactions data from a time series data store
  """

  use Sanbase.Influxdb.Store

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.ExternalServices.Etherscan.Store

  @last_block_measurement "sanbase-internal-last-blocks-measurement"

  def import_last_block_number(address, block_number) do
    Store.delete_by_tag(@last_block_measurement, "address", address)

    %Sanbase.Influxdb.Measurement{
      timestamp: DateTime.utc_now() |> DateTime.to_unix(:nanoseconds),
      fields: %{block_number: block_number |> String.to_integer()},
      tags: [address: address],
      name: @last_block_measurement
    }
    |> Store.import()
  end

  def last_block_number(address) do
    select_last_block_number(address)
    |> Store.query()
    |> parse_last_block_number()
  end

  def last_block_number!(address) do
    case last_block_number(address) do
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

  defp select_last_block_number(address) do
    ~s/SELECT block_number from "sanbase-internal-last-blocks-measurement"
    WHERE address = '#{address}'/
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
    [[_iso8601_datetime, block_number] | _] = block_number
    {:ok, block_number}
  end

  defp parse_last_block_number(_), do: {:ok, nil}
end
