defmodule Sanbase.Contract.MetricAdapter.SqlQuery do
  @moduledoc false
  import Sanbase.Metric.SqlQuery.Helper, only: [to_unix_timestamp: 3]

  alias Sanbase.Clickhouse.Query

  def first_datetime_query(contract_address) do
    sql = """
    SELECT min(dt)
    FROM eth_receipts
    PREWHERE
      to = {{contract_address}}
    """

    params = %{contract_address: Sanbase.BlockchainAddress.to_internal_format(contract_address)}

    Query.new(sql, params)
  end

  def last_datetime_computed_at_query(contract_address) do
    sql = """
    SELECT max(dt)
    FROM eth_receipts
    PREWHERE
      to = {{contract_address}}
    """

    params = %{contract_address: Sanbase.BlockchainAddress.to_internal_format(contract_address)}

    Query.new(sql, params)
  end

  def timeseries_data_query("contract_transactions_count", contract_address, from, to, interval) do
    sql = """
    SELECT
      #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS time,
      uniqExact(transactionHash)
    FROM eth_receipts
    PREWHERE
      dt >= toDateTime({{from}}) AND
      dt < toDateTime({{to}}) AND
      to = {{contract_address}}
    GROUP BY time
    ORDER BY time
    """

    params = %{
      interval: Sanbase.DateTimeUtils.str_to_sec(interval),
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to),
      contract_address: Sanbase.BlockchainAddress.to_internal_format(contract_address)
    }

    Query.new(sql, params)
  end

  def timeseries_data_query("contract_interacting_addresses_count", contract_address, from, to, interval) do
    sql = """
    SELECT
      #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS time,
      uniqExact(from)
    FROM eth_receipts
    PREWHERE
      dt >= toDateTime({{from}}) AND
      dt < toDateTime({{to}}) AND
      to = {{contract_address}}
    GROUP BY time
    ORDER BY time
    """

    params = %{
      interval: Sanbase.DateTimeUtils.str_to_sec(interval),
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to),
      contract_address: Sanbase.BlockchainAddress.to_internal_format(contract_address)
    }

    Query.new(sql, params)
  end
end
