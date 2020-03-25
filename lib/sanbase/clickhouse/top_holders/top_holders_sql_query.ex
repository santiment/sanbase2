defmodule Sanbase.Clickhouse.TopHolders.SqlQuery do
  @moduledoc false

  import Sanbase.DateTimeUtils
  import Sanbase.Metric.SqlQuery.Helper, only: [aggregation: 3]

  def timeseries_data_query(
        "amount_in_top_holders",
        table,
        contract,
        _blockchain,
        count,
        from,
        to,
        interval,
        decimals,
        aggregation
      ) do
    decimals = Sanbase.Math.ipow(10, decimals)

    query = """
    SELECT dt, SUM(value)
    FROM (
      SELECT
        toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS dt,
        #{aggregation(aggregation, "value", "dt")} / #{decimals} AS value
      FROM #{table} FINAL
      PREWHERE
        contract = ?2 AND
        rank <= ?3 AND
        dt >= toDateTime(?4) AND
        dt < toDateTime(?5) AND
        rank IS NOT NULL
      GROUP BY dt, address
      ORDER BY dt, value desc
      LIMIT ?3 BY dt
    )
    GROUP BY dt
    ORDER BY dt
    """

    args = [
      interval |> str_to_sec(),
      contract,
      count,
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix()
    ]

    {query, args}
  end

  def timeseries_data_query(
        "amount_in_exchange_top_holders",
        table,
        contract,
        blockchain,
        count,
        from,
        to,
        interval,
        decimals,
        aggregation
      ) do
    decimals = Sanbase.Math.ipow(10, decimals)

    query = """
    SELECT dt, SUM(value)
    FROM (
      SELECT
        address,
        toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS dt,
        #{aggregation(aggregation, "value", "dt")} / #{decimals} AS value
      FROM (
        SELECT dt, address, value
        FROM #{table} FINAL
        PREWHERE
          contract = ?2 AND
          dt >= toDateTime(?4) AND
          dt < toDateTime(?5) AND
          rank IS NOT NULL
      )
      GROUP BY dt, address
      ORDER BY dt, value DESC
      LIMIT ?3 BY dt
    )
    GLOBAL ANY INNER JOIN (
      SELECT address
      FROM blockchain_address_labels
      PREWHERE blockchain = ?6 AND label IN ('centralized_exchange', 'decentralized_exchange')
    ) USING address
    GROUP BY dt
    ORDER BY dt
    """

    args = [
      interval |> str_to_sec(),
      contract,
      count,
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix(),
      blockchain
    ]

    {query, args}
  end

  def timeseries_data_query(
        "amount_in_non_exchange_top_holders",
        table,
        contract,
        blockchain,
        count,
        from,
        to,
        interval,
        decimals,
        aggregation
      ) do
    decimals = Sanbase.Math.ipow(10, decimals)

    query = """
    SELECT dt, SUM(value)
    FROM (
      SELECT
        #{aggregation(aggregation, "value", "dt")} / #{decimals} AS value,
        toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS dt,
        address
      FROM #{table} FINAL
      PREWHERE
        address GLOBAL NOT IN (
          SELECT address
          FROM blockchain_address_labels
          PREWHERE blockchain = ?6 AND label IN ('centralized_exchange', 'decentralized_exchange')
        ) AND
        contract = ?2 AND
        dt >= toDateTime(?4) AND
        dt < toDateTime(?5) AND
        rank IS NOT NULL
      GROUP BY dt, address
      ORDER BY dt, value DESC
      LIMIT ?3 BY dt
    )
    GROUP BY dt
    ORDER BY dt
    """

    args = [
      interval |> str_to_sec(),
      contract,
      count,
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix(),
      blockchain
    ]

    {query, args}
  end

  def first_datetime_query(table, contract) do
    query = """
    SELECT
      toUnixTimestamp(toDateTime(min(dt)))
    FROM #{table}
    PREWHERE
      contract = ?1
    """

    args = [contract]
    {query, args}
  end

  def last_datetime_computed_at_query(table, contract) do
    query = """
    SELECT
      toUnixTimestamp(argMax(computed_at, dt))
    FROM #{table} FINAL
    PREWHERE
      contract = ?1
    """

    args = [contract]

    {query, args}
  end
end
