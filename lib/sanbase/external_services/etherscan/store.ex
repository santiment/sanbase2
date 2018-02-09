defmodule Sanbase.ExternalServices.Etherscan.Store do
  @moduledoc ~S"""
    A module for storing and fetching transactions data from a time series data store
  """

  use Sanbase.Influxdb.Store

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.ExternalServices.Etherscan.Store

  @last_block_measurement "sanbase-internal-last-blocks-measurement"

  @doc ~s"""
    Updates the point for `address` in the special measurement used for saving
    the last queried block number for a given address.
  """
  @spec import_last_block_number(String.t(), String.t()) :: :ok | no_return()
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

  @doc ~s"""
    Returns the last block number that was quried for that particular address.
    Returns `{:ok, result}` on successs, `{:error, reason}` otherwise
  """
  @spec last_block_number(String.t()) :: {:ok, Integer} | {:ok, nil} | {:error, String.t()}
  def last_block_number(address) do
    select_last_block_number(address)
    |> Store.query()
    |> parse_last_block_number()
  end

  @doc ~s"""
    Returns the last block number that was quried for that particular address.
    Returns `result` on result, raises an error otherwise
  """
  @spec last_block_number!(String.t()) :: Integer | nil | no_return()
  def last_block_number!(address) do
    case last_block_number(address) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end

  @doc ~s"""
    Returns the sum of transactions over the specified period of time.
    The `transaction_type` should be either `in` or `out` string.
    Returns `{:ok, result}` on success, `{:error, reason}` otherwise
  """
  @spec trx_sum_in_interval(String.t(), %DateTime{}, %DateTime{}, String.t()) ::
          {:ok, list()} | {:error, String.t()}
  def trx_sum_in_interval(measurement, from, to, transaction_type) do
    sum_from_to_query(measurement, from, to, transaction_type)
    |> Store.query()
    |> parse_trx_sum_time_series()
  end

  @doc ~s"""
    Returns the sum of transactions over the specified period of time.
    The `transaction_type` should be either `in` or `out` string.
    Returns `result` on success, raises an error otherwise
  """
  @spec trx_sum_in_interval!(String.t(), %DateTime{}, %DateTime{}, String.t()) ::
          list() | nil | no_return()
  def trx_sum_in_interval!(measurement, from, to, transaction_type) do
    case trx_sum_in_interval(measurement, from, to, transaction_type) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end

  # Private functions

  defp select_last_block_number(address) do
    ~s/SELECT block_number from "sanbase-internal-last-blocks-measurement"
    WHERE address = '#{address}'/
  end

  defp sum_from_to_query(measurement, from, to, transaction_type) do
    ~s/SELECT time, SUM(trx_value)
    FROM "#{measurement}"
    WHERE transaction_type = '#{transaction_type}'
    AND time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
  end

  defp parse_trx_sum_time_series(%{results: [%{error: error}]}) do
    {:error, error}
  end

  defp parse_trx_sum_time_series(%{
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
    [[_iso8601_datetime, trx_value]] = transactions

    {:ok, trx_value}
  end

  defp parse_trx_sum_time_series(_), do: {:ok, []}

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
