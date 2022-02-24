defmodule Sanbase.Contract.MetricAdapter.SqlQuery do
  def first_datetime_query(contract_address) do
    query = """
    SELECT min(dt)
    FROM eth_receipts
    PREWHERE
      to = ?1
    """

    args = [Sanbase.BlockchainAddress.to_internal_format(contract_address)]
    {query, args}
  end

  def last_datetime_computed_at_query(contract_address) do
    query = """
    SELECT max(dt)
    FROM eth_receipts
    PREWHERE
      to = ?1
    """

    args = [Sanbase.BlockchainAddress.to_internal_format(contract_address)]
    {query, args}
  end

  def timeseries_data_query("contract_transactions_count", contract_address, from, to, interval) do
    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
      uniqExact(transactionHash)
    FROM eth_receipts
    PREWHERE
      dt >= toDateTime(?2) AND
      dt < toDateTime(?3) AND
      to = ?4
    GROUP BY time
    ORDER BY time
    """

    args = [
      Sanbase.DateTimeUtils.str_to_sec(interval),
      DateTime.to_unix(from),
      DateTime.to_unix(to),
      Sanbase.BlockchainAddress.to_internal_format(contract_address)
    ]

    {query, args}
  end

  def timeseries_data_query(
        "contract_interacting_addresses_count",
        contract_address,
        from,
        to,
        interval
      ) do
    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
      uniqExact(from)
    FROM eth_receipts
    PREWHERE
      dt >= toDateTime(?2) AND
      dt < toDateTime(?3) AND
      to = ?4
    GROUP BY time
    ORDER BY time
    """

    args = [
      Sanbase.DateTimeUtils.str_to_sec(interval),
      DateTime.to_unix(from),
      DateTime.to_unix(to),
      Sanbase.BlockchainAddress.to_internal_format(contract_address)
    ]

    {query, args}
  end
end
