defmodule Sanbase.Balance.SqlQuery do
  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]

  def historical_balance_changes_query(
        addresses,
        slug,
        decimals,
        blockchain,
        from,
        to,
        interval
      ) do
    interval = Sanbase.DateTimeUtils.str_to_sec(interval)
    to_unix = DateTime.to_unix(to)
    from_unix = DateTime.to_unix(from)
    span = div(to_unix - from_unix, interval) |> max(1)

    balance_changes_query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
      toFloat64(balance_change / ?5) AS balance_change
    FROM (
      SELECT
        dt,
        balance_change
      FROM (
        SELECT
          arraySort(x-> x.1, arrayReduce('groupUniqArray', groupArrayMerge(values))) AS _sorted,
          arrayPushFront(_sorted, tuple(toDateTime(0), toFloat64(0))) AS sorted,
          arrayMap(x-> x.1, sorted) AS dates,
          arrayMap(x-> x.2, sorted) AS balances,
          arrayDifference(balances) AS balance_changes
        FROM balances_aggregated
        WHERE
          #{address_clause(addresses, argument_position: 2)} AND
          blockchain = ?3 AND
          asset_ref_id = (SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = ?4 LIMIT 1)
        GROUP BY address, blockchain, asset_ref_id
      )
      ARRAY JOIN dates AS dt, balance_changes AS balance_change
      WHERE dt >= toDateTime(?6) AND dt < toDateTime(?7)
    )
    """

    query = """
    SELECT time, SUM(balance_change)
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(?6 + number * ?1), ?1) * ?1) AS time,
          toFloat64(0) AS balance_change
        FROM numbers(?8)

      UNION ALL

      #{balance_changes_query}
    )
    GROUP BY time
    ORDER BY time
    """

    args = [
      interval,
      addresses,
      blockchain,
      slug,
      Sanbase.Math.ipow(10, decimals),
      from_unix,
      to_unix,
      span
    ]

    {query, args}
  end

  def balance_change_query(addresses, slug, decimals, blockchain, from, to) do
    query = """
    SELECT
      address,
      argMaxIf(value, dt, dt <= ?4) / ?6 AS start_balance,
      argMaxIf(value, dt, dt <= ?5) / ?6 AS end_balance,
      end_balance - start_balance AS diff
    FROM (
      SELECT
        address,
        arrayJoin(arrayReduce('groupUniqArray', groupArrayMerge(values))) AS values_merged,
        values_merged.1 AS dt,
        values_merged.2 AS value
      FROM balances_aggregated
      WHERE
        #{address_clause(addresses, argument_position: 1)} AND
        blockchain = ?2 AND
        asset_ref_id = ( SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = ?3 LIMIT 1 )
      GROUP BY address, blockchain, asset_ref_id
    )
    GROUP BY address
    """

    args = [
      addresses,
      blockchain,
      slug,
      DateTime.to_unix(from),
      DateTime.to_unix(to),
      Sanbase.Math.ipow(10, decimals)
    ]

    {query, args}
  end

  def historical_balance_query(
        address,
        slug,
        decimals,
        blockchain,
        from,
        to,
        interval
      ) do
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)
    interval_sec = str_to_sec(interval)
    span = div(to_unix - from_unix, interval_sec) |> max(1)

    query = """
     SELECT time, SUM(value), toUInt8(SUM(has_changed))
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(?5 + number * ?1), ?1) * ?1) AS time,
          toFloat64(0) AS value,
          toUInt8(0) AS has_changed
        FROM numbers(?7)

      UNION ALL

      SELECT
        toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
        toFloat64(argMax(value, dt)) / ?8 AS value,
        toUInt8(1) AS has_changed
      FROM (
        SELECT
          arrayJoin(groupArrayMerge(values)) AS values_merged,
          values_merged.1 AS dt,
          values_merged.2 AS value
        FROM balances_aggregated
        WHERE
          #{address_clause(address, argument_position: 2)} AND
          blockchain = ?3 AND
          asset_ref_id = ( SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = ?4 LIMIT 1 )
        GROUP BY address, blockchain, asset_ref_id
        HAVING dt >= toDateTime(?5) AND dt < toDateTime(?6)
      )
      GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    args = [
      interval_sec,
      address,
      blockchain,
      slug,
      from_unix,
      to_unix,
      span,
      Sanbase.Math.ipow(10, decimals)
    ]

    {query, args}
  end

  def historical_balance_ohlc_query(
        address,
        slug,
        decimals,
        blockchain,
        from,
        to,
        interval
      ) do
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)
    interval_sec = str_to_sec(interval)
    span = div(to_unix - from_unix, interval_sec) |> max(1)

    query = """
    SELECT
      time, SUM(open) AS open,
      SUM(high) AS high,
      SUM(low) AS low,
      SUM(close) AS close,
      toUInt8(SUM(has_changed))
    FROM (
      SELECT
        toUnixTimestamp(intDiv(toUInt32(?5 + number * ?1), ?1) * ?1) AS time,
        toFloat64(0) AS open,
        toFloat64(0) AS high,
        toFloat64(0) AS low,
        toFloat64(0) AS close,
        toUInt8(0) AS has_changed
      FROM numbers(?7)

      UNION ALL

      SELECT
        toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
        toFloat64(argMin(value, dt)) / ?8 AS open,
        toFloat64(max(value)) / ?8 AS high,
        toFloat64(min(value)) / ?8 AS low,
        toFloat64(argMax(value, dt)) / ?8 AS close,
        toUInt8(1) AS has_changed
      FROM (
        SELECT
          arrayJoin(groupArrayMerge(values)) AS values_merged,
          values_merged.1 AS dt,
          values_merged.2 AS value
        FROM balances_aggregated
        WHERE
          #{address_clause(address, argument_position: 2)} AND
          blockchain = ?3 AND
          asset_ref_id = ( SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = ?4 LIMIT 1 )
        GROUP BY address, blockchain, asset_ref_id
        HAVING dt >= toDateTime(?5) AND dt < toDateTime(?6)
      )
      GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    args = [
      interval_sec,
      address,
      blockchain,
      slug,
      from_unix,
      to_unix,
      span,
      Sanbase.Math.ipow(10, decimals)
    ]

    {query, args}
  end

  def current_balance_query(addresses, slug, decimals, blockchain) do
    query = """
    SELECT
      address,
      argMax(value, dt) / ?4 AS balance
    FROM (
      SELECT
        address,
        arrayJoin(groupArrayMerge(values)) AS values_merged,
        values_merged.1 AS dt,
        values_merged.2 AS value
      FROM balances_aggregated
      WHERE
        #{address_clause(addresses, argument_position: 1)} AND
        blockchain = ?2 AND
        asset_ref_id = ( SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = ?3 LIMIT 1 )
      GROUP BY address
    )
    GROUP BY address
    """

    args = [addresses, blockchain, slug, Sanbase.Math.ipow(10, decimals)]

    {query, args}
  end

  def first_datetime_query(address, slug, blockchain) when is_binary(address) do
    query = """
    SELECT toUnixTimestamp(min(dt))
    FROM (
      SELECT arrayJoin(groupArrayMerge(values)) AS values_merged, values_merged.1 AS dt
      FROM balances_aggregated
      WHERE
        #{address_clause(address, argument_position: 1)} AND
        blockchain = ?2 AND
        asset_ref_id = ( SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = ?3 LIMIT 1 )
    )
    """

    args = [address, blockchain, slug]
    {query, args}
  end

  def assets_held_by_address_query(address) do
    query = """
    SELECT
      name,
      argMax(value, dt) / pow(10, decimals) AS balance
    FROM (
      SELECT
        address,
        asset_ref_id,
        arrayJoin(groupArrayMerge(values)) AS values_merged,
        values_merged.1 AS dt,
        values_merged.2 AS value
      FROM balances_aggregated
      WHERE
        #{address_clause(address, argument_position: 1)}
      GROUP BY address, blockchain, asset_ref_id
    )
    INNER JOIN (
      SELECT asset_ref_id, name, decimals
      FROM asset_metadata FINAL
    ) USING (asset_ref_id)
    GROUP BY address, asset_ref_id, name, decimals
    """

    args = [address]

    {query, args}
  end

  def last_balance_before_query(addresses, slug, decimals, blockchain, datetime) do
    query = """
    SELECT
      address,
      argMax(value, dt) / ?5 AS last_value_before
    FROM (
      SELECT
        address,
        arrayJoin(groupArrayMerge(values)) AS values_merged,
        values_merged.1 AS dt,
        values_merged.2 AS value
      FROM balances_aggregated
      WHERE
        #{address_clause(addresses, argument_position: 1)} AND
        blockchain = ?2 AND
        asset_ref_id = ( SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = ?3 LIMIT 1 )
      GROUP BY address, blockchain, asset_ref_id
      HAVING dt < toDateTime(?4)
    )
    GROUP BY address
    """

    args = [
      addresses,
      blockchain,
      slug,
      DateTime.to_unix(datetime),
      Sanbase.Math.ipow(10, decimals)
    ]

    {query, args}
  end

  defp address_clause(address, opts) when is_binary(address) do
    position = Keyword.fetch!(opts, :argument_position)
    "address = ?#{position}"
  end

  defp address_clause(addresses, opts) when is_list(addresses) do
    position = Keyword.fetch!(opts, :argument_position)
    "address IN (?#{position})"
  end
end
