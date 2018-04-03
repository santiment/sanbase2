defmodule Sanbase.ExternalServices.Etherscan.Store do
  @moduledoc ~S"""
    A module for storing and fetching transactions data from a time series data store
  """

  use Sanbase.Influxdb.Store

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.ExternalServices.Etherscan.Store
  alias Sanbase.Model.Project

  @last_block_measurement "sanbase-internal-last-blocks-measurement"

  def internal_measurements() do
    {:ok, [@last_block_measurement]}
  end

  def import_last_block_number(_, nil), do: :ok

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
    |> parse_time_series()
    |> case do
      {:error, error} -> {:error, error}
      {:ok, [[_iso8601_datetime, block_number] | _]} -> {:ok, block_number}
      {:ok, _} -> {:ok, nil}
    end
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
          {:ok, number()} | {:ok, nil} | {:error, String.t()}
  def trx_sum_in_interval(measurement, from, to, transaction_type) do
    sum_from_to_query(measurement, from, to, transaction_type)
    |> Store.query()
    |> parse_time_series()
    |> case do
      {:ok, [[_datetime, amount]]} -> {:ok, amount}
      {:ok, []} -> {:ok, nil}
      res -> res
    end
  end

  @doc ~s"""
    Returns the sum of transactions over the specified period of time.
    The `transaction_type` should be either `in` or `out` string.
    Returns `result` on success, raises an error otherwise
  """
  @spec trx_sum_in_interval!(String.t(), %DateTime{}, %DateTime{}, String.t()) ::
          number() | nil | no_return()
  def trx_sum_in_interval!(measurement, from, to, transaction_type) do
    case trx_sum_in_interval(measurement, from, to, transaction_type) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end

  @doc ~s"""
    Returns the sum of the total ETH spent of all projects from the `measurements_list`
    Influxdb does _not_ support mathematics over multiple measurements. The SUM of
    the transactions is aggreated in influxdb for each measurement and the total SUM
    is calculated in Elixir
  """
  @spec eth_spent_by_projects(list(), %DateTime{}, %DateTime{}) ::
          {:ok, number()} | {:ok, nil} | {:error, String.t()}
  def eth_spent_by_projects([], _from, _to), do: {:ok, nil}

  def eth_spent_by_projects(measurements_list, from, to) do
    total_eth_spent =
      measurements_list
      |> Stream.map(&trx_sum_in_interval(&1, from, to, "out"))
      |> Stream.reject(fn {:ok, sum} -> sum == nil end)
      |> Enum.reduce(0, fn
        {:ok, sum}, acc ->
          acc + sum

        {:error, error}, acc ->
          Logger.warn(
            "Error while calculating the total eth spent by a project in an interval: #{error}"
          )

          acc
      end)

    {:ok, total_eth_spent}
  end

  @doc ~s"""
    Returns the sum of 'out' transactions over the specified period of time for all projecs,
    grouped by the specified resolution.
    Influxdb does _not_ support mathematics over multiple measurements. The SUM of
    the transactions is aggreated in influxdb for each measurement and the total SUM
    is calculated in Elixir
  """
  @spec eth_spent_over_time_by_projects(list(), %DateTime{}, %DateTime{}, String.t()) ::
          {:ok, list()} | {:error, String.t()}
  def eth_spent_over_time_by_projects([], _from, _to, _interval), do: {:ok, []}

  def eth_spent_over_time_by_projects(measurements_list, from, to, resolution) do
    total_eth_spent_over_time =
      measurements_list
      |> Stream.map(&trx_sum_over_time_in_interval!(&1, from, to, resolution, "out"))
      |> Enum.reject(fn list -> [] == list end)
      |> Stream.zip()
      |> Stream.map(&Tuple.to_list/1)
      |> Stream.map(&reduce_values/1)

    {:ok, total_eth_spent_over_time}
  end

  @doc ~s"""
    Returns the sum of transactions over the specified period of time, grouped by the specified resolution.
    The `transaction_type` should be either `in` or `out` string.
    Returns `{:ok, result}` on success, `{:error, reason}` otherwise
  """
  @spec trx_sum_over_time_in_interval(
          String.t(),
          %DateTime{},
          %DateTime{},
          String.t(),
          String.t()
        ) :: {:ok, list()} | {:error, String.t()}
  def trx_sum_over_time_in_interval(measurement, from, to, resolution, transaction_type) do
    sum_over_time_from_to_query(measurement, from, to, resolution, transaction_type)
    |> Store.query()
    |> parse_time_series()
  end

  @doc ~s"""
    Returns the sum of transactions over the specified period of time, grouped by the specified resolution.
    The `transaction_type` should be either `in` or `out` string.
    Returns `result` on success, raises an error otherwise
  """
  @spec trx_sum_over_time_in_interval!(
          String.t(),
          %DateTime{},
          %DateTime{},
          String.t(),
          String.t()
        ) :: list() | no_return()
  def trx_sum_over_time_in_interval!(measurement, from, to, resolution, transaction_type) do
    case trx_sum_over_time_in_interval(measurement, from, to, resolution, transaction_type) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end

  @doc ~s"""
    Return list of all transactions for the given measurement, time period and
    transaction type. Supported transaction types are `all`, `in` and `out`. Returns
    `{:ok, result}` on success, `{:error, error}` otherwise.
  """
  @spec top_transactions(
          String.t(),
          %DateTime{},
          %DateTime{},
          String.t(),
          String.t()
        ) :: {:ok, list()} | {:error, String.t()}
  def top_transactions(measurement, from, to, transaction_type, limit) do
    select_top_transactions(measurement, from, to, transaction_type, limit)
    |> Store.query()
    |> parse_time_series()
  end

  @doc ~s"""
    Return list of all transactions for the given measurement, time period and
    transaction type. Supported transaction types are `all`, `in` and `out`. Returns
    `result` on success, raises an error otherwise.
  """
  @spec top_transactions!(
          String.t(),
          %DateTime{},
          %DateTime{},
          String.t(),
          String.t()
        ) :: list() | no_return()
  def top_transactions!(measurement, from, to, transaction_type, limit) do
    case top_transactions(measurement, from, to, transaction_type, limit) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end

  # Private functions

  defp reduce_values([]), do: []

  defp reduce_values([[datetime, _] | _] = values) do
    total_eth_spent =
      values
      |> Enum.reduce(0, fn [_, sum], acc ->
        sum + acc
      end)

    [datetime, total_eth_spent]
  end

  defp select_last_block_number(address) do
    ~s/SELECT block_number from "#{@last_block_measurement}"
    WHERE address = '#{address}'/
  end

  defp sum_from_to_query(measurement, from, to, transaction_type) do
    ~s/SELECT time, SUM(trx_value)
    FROM "#{measurement}"
    WHERE trx_hash != ''
    #{construct_internal_eth_addresses_filter(measurement, transaction_type)}
    AND time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
  end

  defp sum_over_time_from_to_query(measurement, from, to, resolution, transaction_type) do
    ~s/SELECT time, SUM(trx_value)
    FROM "#{measurement}"
    WHERE trx_hash != ''
    #{construct_internal_eth_addresses_filter(measurement, transaction_type)}
    AND time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}
    GROUP BY TIME(#{resolution}) fill(0)/
  end

  defp select_top_transactions(measurement, from, to, "all", limit) do
    ~s/SELECT trx_hash, TOP(trx_value, #{limit}) as trx_value, transaction_type, from_addr, to_addr
    FROM "#{measurement}"
    WHERE trx_hash != ''
    #{construct_internal_eth_addresses_filter(measurement, "all")}
    AND time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
  end

  defp select_top_transactions(measurement, from, to, transaction_type, limit) do
    ~s/SELECT trx_hash, TOP(trx_value, #{limit}) as trx_value, transaction_type, from_addr, to_addr
    FROM "#{measurement}"
    WHERE trx_hash != ''
    #{construct_internal_eth_addresses_filter(measurement, transaction_type)}
    AND time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
  end

  defp construct_internal_eth_addresses_filter(ticker, transaction_type) do
    case ticker |> Project.project_eth_addresses_by_ticker() do
      nil ->
        filter_eth_addresses([], transaction_type)

      project ->
        project
        |> Map.get(:eth_addresses)
        |> Enum.map(fn eth_address -> eth_address.address end)
        |> filter_eth_addresses(transaction_type)
    end
  end

  defp filter_eth_addresses([], "all"), do: ""
  defp filter_eth_addresses([], "in"), do: " AND transaction_type = 'in'"
  defp filter_eth_addresses([], "out"), do: " AND transaction_type = 'out'"

  defp filter_eth_addresses(addresses, "in") do
    " AND transaction_type = 'in' AND " <> filter_eth_addresses_by_field(addresses, "from_addr")
  end

  defp filter_eth_addresses(addresses, "out") do
    " AND transaction_type = 'out' AND " <> filter_eth_addresses_by_field(addresses, "to_addr")
  end

  defp filter_eth_addresses(addresses, "all") do
    ~s/(#{filter_eth_addresses(addresses, "in")})/ <>
      " OR " <> ~s/(#{filter_eth_addresses(addresses, "out")})/
  end

  def filter_eth_addresses_by_field(addresses, field) do
    addresses
    |> Stream.map(&filter_address(&1, field))
    |> Enum.join(" AND ")
  end

  defp filter_address(address, field), do: ~s/"#{field}" != '#{address}'/
end
