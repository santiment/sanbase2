defmodule Sanbase.Balance.SqlQuery do
  import Sanbase.Utils.Transform, only: [opts_to_limit_offset: 1]
  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]
  import Sanbase.Metric.SqlQuery.Helper, only: [generate_comparison_string: 3]

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

  # def current_balance_query(
  #       addresses,
  #       _slug = "ethereum",
  #       decimals,
  #       _blockchain,
  #       table
  #     ) do
  #   query = """
  #   SELECT address, argMax(balance, dt) / pow(10, ?2) AS balance
  #   FROM #{table}
  #   WHERE
  #     #{address_clause(addresses, argument_position: 1)} AND
  #     addressType = 'normal'
  #   GROUP BY address
  #   """

  #   args = [addresses, decimals]

  #   {query, args}
  # end

  # def current_balance_query(addresses, slug, decimals, _blockchain = "ethereum", table) do
  #   query = """
  #   SELECT address, argMax(balance, dt) / pow(10, ?3) AS balance
  #   FROM #{table}
  #   WHERE
  #     #{address_clause(addresses, argument_position: 1)} AND
  #     assetRefId = (SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = ?2 LIMIT 1) AND
  #     addressType = 'normal'
  #   GROUP BY address
  #   """

  #   args = [addresses, slug, decimals]

  #   {query, args}
  # end

  def current_balance_query(addresses, slug, decimals, blockchain, _table) do
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

  def addresses_by_filter_query(
        _slug,
        decimals,
        operator,
        threshold,
        "eth_balances_realtime" = table,
        _opts
      ) do
    query = """
    SELECT address, balance
    FROM (
      SELECT address, argMax(balance, dt) / pow(10, ?1) AS balance
      FROM #{table}
      PREWHERE
        addressType = 'normal'
      GROUP BY address
    )
    WHERE #{generate_comparison_string("balance", operator, threshold)}
    LIMIT 10000
    """

    args = [decimals]

    {query, args}
  end

  def addresses_by_filter_query(slug, decimals, operator, threshold, table, _opts) do
    query = """
    SELECT address, balance
    FROM (
      SELECT address, argMax(balance, dt) / pow(10, ?2) AS balance
      FROM #{table}
      PREWHERE
        assetRefId = (SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = ?1 LIMIT 1) AND
        addressType = 'normal'
      GROUP BY address
    )
    WHERE #{generate_comparison_string("balance", operator, threshold)}
    LIMIT 10000
    """

    args = [slug, decimals]

    {query, args}
  end

  def top_addresses_query(_slug, decimals, blockchain, "eth_balances_realtime" = table, opts) do
    direction = if Keyword.get(opts, :direction) == :asc, do: "ASC", else: "DESC"
    labels = Keyword.get(opts, :labels, :all)

    {limit, offset} = opts_to_limit_offset(opts)
    limit = Enum.min([limit, 10_000])
    args = [decimals, limit, offset]

    {labels_join_str, args} = maybe_join_labels(labels, blockchain, args)

    query = """
    SELECT address, balance
    FROM (
      SELECT address, argMax(balance, dt) / pow(10, ?2) AS balance
      FROM #{table}
      PREWHERE
        addressType = 'normal'
      GROUP BY address
    )
    #{labels_join_str}
    WHERE balance > 1e-10
    ORDER BY balance #{direction}
    LIMIT ?3 OFFSET ?4
    """

    {query, args}
  end

  def top_addresses_query(slug, decimals, blockchain, table, opts) do
    direction = if Keyword.get(opts, :direction) == :asc, do: "ASC", else: "DESC"
    labels = Keyword.get(opts, :labels, :all)

    {limit, offset} = opts_to_limit_offset(opts)
    limit = Enum.min([limit, 10_000])
    args = [slug, decimals, limit, offset]

    {labels_join_str, args} = maybe_join_labels(labels, blockchain, args)

    query = """
    SELECT address, balance
    FROM (
      SELECT address, argMax(balance, dt) / pow(10, ?2) AS balance
      FROM #{table}
      PREWHERE
        assetRefId = (SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = ?1 LIMIT 1) AND
        addressType = 'normal'
      GROUP BY address
    )
    #{labels_join_str}
    WHERE balance > 1e-10
    ORDER BY balance #{direction}
    LIMIT ?3 OFFSET ?4
    """

    {query, args}
  end

  defp maybe_join_labels(:all, _blockchain, args), do: {"", args}

  defp maybe_join_labels([_ | _] = labels, blockchain, args) do
    args_length = length(args)

    str = """
    GLOBAL ANY INNER JOIN
    (
      SELECT address
      FROM blockchain_address_labels
      PREWHERE blockchain = ?#{args_length + 1} AND label IN (?#{args_length + 2})
    ) USING (address)
    """

    labels = Enum.map(labels, &String.downcase/1)
    {str, args ++ [blockchain, labels]}
  end

  def assets_held_by_address_changes_query(address, datetime) do
    query = """
    SELECT
      name,
      greatest(argMaxIf(value, dt, dt <= toDateTime(?2)) / pow(10, decimals), 0) AS previous_balance,
      greatest(argMax(value, dt) / pow(10, decimals), 0) AS current_balance,
      current_balance - previous_balance AS balance_change
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
    HAVING previous_balance > 0 AND current_balance > 0
    """

    args = [address, DateTime.to_unix(datetime)]

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
    HAVING balance > 0
    """

    args = [address]

    {query, args}
  end

  def usd_value_held_by_address_query(address) do
    # It has `name` and `balance` as fields
    {query, args} = assets_held_by_address_query(address)

    query = """
    SELECT name, balance, price_usd, balance * price_usd AS usd_value
    FROM (
      #{query}
    )
    INNER JOIN
    (
      SELECT slug AS name, argMax(price_usd, dt) AS price_usd
      FROM asset_prices_v3
      PREWHERE dt >= now() - interval 12 hour
      GROUP BY name
    ) USING (name)
    HAVING usd_value > 0
    """

    {query, args}
  end

  def usd_value_address_change_query(address, datetime) do
    # It has `name` and `balance` as fields
    {query, args} = assets_held_by_address_changes_query(address, datetime)

    query = """
    SELECT
      name,
      previous_balance,
      current_balance,
      previous_price_usd,
      current_price_usd,
      previous_balance * previous_price_usd AS previous_usd_value,
      current_balance * current_price_usd AS current_usd_value
    FROM (
      #{query}
    )
    INNER JOIN
    (
      SELECT slug AS name,
        argMax(price_usd, dt) AS current_price_usd,
        argMaxIf(price_usd, dt, dt <= toDateTime(?2)) AS previous_price_usd
      FROM asset_prices_v3
      PREWHERE (dt >= now() - interval 24 hour) OR (dt >= toDateTime(?2) - interval 24 hour AND dt <= toDateTime(?2))
      GROUP BY name
    ) USING (name)
    """

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
