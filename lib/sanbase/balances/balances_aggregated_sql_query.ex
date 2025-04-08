defmodule Sanbase.Balance.BalancesAggregatedSqlQuery do
  import Sanbase.Utils.Transform, only: [opts_to_limit_offset: 1]
  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]

  import Sanbase.Metric.SqlQuery.Helper,
    only: [generate_comparison_string: 3, timerange_parameters: 3]

  def historical_balance_changes_query(
        addresses,
        slug,
        decimals,
        blockchain,
        from,
        to,
        interval
      ) do
    balance_changes_sql = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(dt), {{interval}}) * {{interval}}) AS time,
      toFloat64(balance_change / {{decimals}}) AS balance_change
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
          #{address_clause(addresses, argument_name: "addresses")} AND
          blockchain = {{blockchain}} AND
          asset_ref_id = (SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = {{slug}} LIMIT 1)
        GROUP BY address
      )
      ARRAY JOIN dates AS dt, balance_changes AS balance_change
      WHERE dt >= toDateTime({{from}}) AND dt < toDateTime({{to}})
    )
    """

    sql = """
    SELECT time, SUM(balance_change)
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32({{from}} + number * {{interval}}), {{interval}}) * {{interval}}) AS time,
          toFloat64(0) AS balance_change
        FROM numbers({{span}})

      UNION ALL

      #{balance_changes_sql}
    )
    GROUP BY time
    ORDER BY time
    """

    {from, to, interval, span} = timerange_parameters(from, to, interval)

    params = %{
      interval: interval,
      addresses: addresses,
      blockchain: blockchain,
      slug: slug,
      decimals: Integer.pow(10, decimals),
      from: from,
      to: to,
      span: span
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def balance_change_query(addresses, slug, decimals, blockchain, from, to) do
    sql = """
    SELECT
      address,
      argMaxIf(value, dt, dt <= {{from}}) / {{decimals}} AS start_balance,
      argMaxIf(value, dt, dt <= {{to}}) / {{decimals}} AS end_balance,
      end_balance - start_balance AS diff
    FROM (
      SELECT
        address,
        arrayJoin(groupArrayMerge(values)) AS values_merged,
        values_merged.1 AS dt,
        values_merged.2 AS value
      FROM balances_aggregated
      WHERE
        #{address_clause(addresses, argument_name: "addresses")} AND
        blockchain = {{blockchain}} AND
        asset_ref_id = ( SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = {{slug}} LIMIT 1 )
      GROUP BY address
      HAVING dt <= toDateTime({{to}})
    )
    GROUP BY address
    """

    params = %{
      addresses: addresses,
      blockchain: blockchain,
      slug: slug,
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to),
      decimals: Integer.pow(10, decimals)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
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
    sql = """
     SELECT time, SUM(value), toUInt8(SUM(has_changed))
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32({{from}} + number * {{interval}}), {{interval}}) * {{interval}}) AS time,
          toFloat64(0) AS value,
          toUInt8(0) AS has_changed
        FROM numbers({{span}})

      UNION ALL

      SELECT
        toUnixTimestamp(intDiv(toUInt32(dt), {{interval}}) * {{interval}}) AS time,
        toFloat64(argMax(value, dt)) / {{decimals}} AS value,
        toUInt8(1) AS has_changed
      FROM (
        SELECT
          arrayJoin(groupArrayMerge(values)) AS values_merged,
          values_merged.1 AS dt,
          values_merged.2 AS value
        FROM balances_aggregated
        WHERE
          #{address_clause(address, argument_name: "address")} AND
          blockchain = {{blockchain}} AND
          asset_ref_id = ( SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = {{slug}} LIMIT 1 )
        GROUP BY address, blockchain, asset_ref_id
        HAVING dt >= toDateTime({{from}}) AND dt < toDateTime({{to}})
      )
      GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)
    interval_sec = str_to_sec(interval)
    span = div(to_unix - from_unix, interval_sec) |> max(1)

    params = %{
      interval: interval_sec,
      address: address,
      blockchain: blockchain,
      slug: slug,
      from: from_unix,
      to: to_unix,
      span: span,
      decimals: Integer.pow(10, decimals)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
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
    sql = """
    SELECT
      time, SUM(open) AS open,
      SUM(high) AS high,
      SUM(low) AS low,
      SUM(close) AS close,
      toUInt8(SUM(has_changed))
    FROM (
      SELECT
        toUnixTimestamp(intDiv(toUInt32({{from}} + number * {{interval}}), {{interval}}) * {{interval}}) AS time,
        toFloat64(0) AS open,
        toFloat64(0) AS high,
        toFloat64(0) AS low,
        toFloat64(0) AS close,
        toUInt8(0) AS has_changed
      FROM numbers({{span}})

      UNION ALL

      SELECT
        toUnixTimestamp(intDiv(toUInt32(dt), {{interval}}) * {{interval}}) AS time,
        toFloat64(argMin(value, dt)) / {{decimals}} AS open,
        toFloat64(max(value)) / {{decimals}} AS high,
        toFloat64(min(value)) / {{decimals}} AS low,
        toFloat64(argMax(value, dt)) / {{decimals}} AS close,
        toUInt8(1) AS has_changed
      FROM (
        SELECT
          arrayJoin(groupArrayMerge(values)) AS values_merged,
          values_merged.1 AS dt,
          values_merged.2 AS value
        FROM balances_aggregated
        WHERE
          #{address_clause(address, argument_name: "address")} AND
          blockchain = {{blockchain}} AND
          asset_ref_id = ( SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = {{slug}} LIMIT 1 )
        GROUP BY address, blockchain, asset_ref_id
        HAVING dt >= toDateTime({{from}}) AND dt < toDateTime({{to}})
      )
      GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)
    interval_sec = str_to_sec(interval)
    span = div(to_unix - from_unix, interval_sec) |> max(1)

    params = %{
      interval: interval_sec,
      address: address,
      blockchain: blockchain,
      slug: slug,
      from: from_unix,
      to: to_unix,
      span: span,
      decimals: Integer.pow(10, decimals)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def current_balance_query(addresses, slug, decimals, blockchain, _table) do
    sql = """
    SELECT
      address,
      argMax(value, dt) / {{decimals}} AS balance
    FROM (
      SELECT
        address,
        arrayJoin(groupArrayMerge(values)) AS values_merged,
        values_merged.1 AS dt,
        values_merged.2 AS value
      FROM balances_aggregated
      WHERE
        #{address_clause(addresses, argument_name: "addresses")} AND
        blockchain = {{blockchain}} AND
        asset_ref_id = ( SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = {{slug}} LIMIT 1 )
      GROUP BY address
    )
    GROUP BY address
    """

    params = %{
      addresses: addresses,
      blockchain: blockchain,
      slug: slug,
      decimals: Integer.pow(10, decimals)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def first_datetime_query(address, slug, blockchain) when is_binary(address) do
    sql = """
    SELECT toUnixTimestamp(min(dt))
    FROM (
      SELECT
        arrayJoin(groupArrayMerge(values)) AS values_merged,
        values_merged.1 AS dt
      FROM balances_aggregated
      WHERE
        #{address_clause(address, argument_name: "address")} AND
        blockchain = {{blockchain}} AND
        asset_ref_id = ( SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = {{slug}} LIMIT 1 )
    )
    """

    params = %{address: address, blockchain: blockchain, slug: slug}
    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def addresses_by_filter_query(
        _slug,
        decimals,
        operator,
        threshold,
        "eth_balances" = table,
        _opts
      ) do
    sql = """
    SELECT address, balance
    FROM (
      SELECT address, argMax(balance, dt) / pow(10, {{decimals}}) AS balance
      FROM #{table}
      PREWHERE
        addressType = 'normal'
      GROUP BY address
    )
    WHERE #{generate_comparison_string("balance", operator, threshold)}
    LIMIT 10000
    """

    params = %{decimals: decimals}

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def addresses_by_filter_query(slug, decimals, operator, threshold, table, _opts) do
    sql = """
    SELECT address, balance
    FROM (
      SELECT
        address,
        argMax(balance, dt) / pow(10, {{decimals}}) AS balance
      FROM #{table}
      PREWHERE
        assetRefId = (SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = {{slug}} LIMIT 1) AND
        addressType = 'normal'
      GROUP BY address
    )
    WHERE #{generate_comparison_string("balance", operator, threshold)}
    LIMIT 10000
    """

    params = %{
      slug: slug,
      decimals: decimals
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def top_addresses_query(_slug, decimals, blockchain, "eth_balances" = table, opts) do
    direction = if Keyword.get(opts, :direction) == :asc, do: "ASC", else: "DESC"
    labels = Keyword.get(opts, :labels, :all)

    {limit, offset} = opts_to_limit_offset(opts)
    limit = Enum.min([limit, 10_000])

    params = %{decimals: decimals, limit: limit, offset: offset}

    {labels_join_str, params} = maybe_join_labels(labels, blockchain, params)

    sql = """
    SELECT address, balance
    FROM (
        SELECT
          ebr.address,
          argMax(ebr.balance, ebr.dt) / pow(10, {{decimals}}) AS balance
      FROM #{table} AS ebr
      WHERE (ebr.address GLOBAL IN (
        SELECT address
        FROM eth_top_holders_daily
        WHERE value > 1e10 AND(dt = toStartOfDay(today() - toIntervalDay(1))) AND (rank > 0)
        ORDER BY value #{direction}
        LIMIT {{limit}}*2
      )) AND (ebr.addressType = 'normal')
      GROUP BY ebr.address
    )
    #{labels_join_str}
    ORDER BY balance #{direction}
    LIMIT {{limit}}
    OFFSET {{offset}}
    """

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def top_addresses_query(slug, decimals, blockchain, table, opts) do
    direction = if Keyword.get(opts, :direction) == :asc, do: "ASC", else: "DESC"
    labels = Keyword.get(opts, :labels, :all)

    {limit, offset} = opts_to_limit_offset(opts)
    limit = Enum.min([limit, 10_000])

    params = %{
      slug: slug,
      decimals: Integer.pow(10, decimals),
      limit: limit,
      offset: offset
    }

    {labels_join_str, params} = maybe_join_labels(labels, blockchain, params)

    sql = """
    SELECT address, balance
    FROM (
      SELECT address, argMax(balance, dt) / {{decimals}}AS balance
      FROM #{table}
      PREWHERE
        assetRefId = (SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = {{slug}} LIMIT 1) AND
        addressType = 'normal' AND (dt > (now() - toIntervalDay(1)))
      GROUP BY address
    )
    #{labels_join_str}
    WHERE balance > 1e-10
    ORDER BY balance #{direction}
    LIMIT {{limit}} OFFSET {{offset}}
    """

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp maybe_join_labels(:all, _blockchain, params), do: {"", params}

  defp maybe_join_labels([_ | _] = labels, blockchain, params) do
    params_count = map_size(params)
    labels_key = "label_#{params_count + 1}"
    blockchain_key = "blockchain_#{params_count + 2}"

    join_str = """
    GLOBAL ANY INNER JOIN
    (
      SELECT address
      FROM current_label_addresses
      WHERE blockchain = {{#{blockchain_key}}} AND
      label_id IN (
        SELECT label_id FROM label_metadata WHERE key IN ({{#{labels_key}}})
      )
    ) USING (address)
    """

    labels = Enum.map(labels, &String.downcase/1)
    params = Map.merge(params, %{labels_key => labels, blockchain_key => blockchain})
    {join_str, params}
  end

  def assets_held_by_address_changes_query(address, datetime, _table, _opts \\ []) do
    sql = """
    SELECT
      name,
      greatest(argMaxIf(value, dt, dt <= toDateTime({{datetime}})) / pow(10, decimals), 0) AS previous_balance,
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
        #{address_clause(address, argument_name: "address")}
      GROUP BY address, blockchain, asset_ref_id
    )
    INNER JOIN (
      SELECT asset_ref_id, name, decimals
      FROM asset_metadata FINAL
    ) USING (asset_ref_id)
    GROUP BY address, asset_ref_id, name, decimals
    HAVING previous_balance > 0 AND current_balance > 0
    """

    params = %{address: address, datetime: DateTime.to_unix(datetime)}

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def assets_held_by_address_query(address, _table, opts \\ []) do
    sql = """
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
        #{address_clause(address, argument_name: "address")}
      GROUP BY address, blockchain, asset_ref_id
    )
    INNER JOIN (
      SELECT asset_ref_id, name, decimals
      FROM asset_metadata FINAL
    ) USING (asset_ref_id)
    GROUP BY address, asset_ref_id, name, decimals
    #{if Keyword.get(opts, :show_assets_with_zero_balance, false), do: "", else: "HAVING balance > 0"}
    """

    params = %{address: address}

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def usd_value_address_change_query(address, datetime, table, opts \\ []) do
    query_struct = assets_held_by_address_changes_query(address, datetime, table, opts)

    sql = """
    SELECT
      name,
      previous_balance,
      current_balance,
      previous_price_usd,
      current_price_usd,
      previous_balance * previous_price_usd AS previous_usd_value,
      current_balance * current_price_usd AS current_usd_value
    FROM (
      #{query_struct.sql}
    )
    INNER JOIN
    (
      SELECT slug AS name,
        argMax(price_usd, dt) AS current_price_usd,
        argMaxIf(price_usd, dt, dt <= toDateTime({{datetime}})) AS previous_price_usd
      FROM asset_prices_v3
      WHERE
        dt >= now() - INTERVAL 24 HOUR OR
        (
          dt >= toDateTime({{datetime}}) - INTERVAL 24 HOUR AND
          dt <= toDateTime({{datetime}})
        )
      GROUP BY name
    ) USING (name)
    """

    Sanbase.Clickhouse.Query.put_sql(query_struct, sql)
  end

  def usd_value_held_by_address_query(address, table, opts \\ []) do
    query_struct = assets_held_by_address_query(address, table, opts)

    sql = """
    SELECT
      name,
      balance,
      price_usd,
      balance * price_usd AS usd_value
    FROM (
      #{query_struct.sql}
    )
    INNER JOIN
    (
      SELECT
        slug AS name,
        argMax(price_usd, dt) AS price_usd
      FROM asset_prices_v3
      WHERE dt >= now() - INTERVAL 24 HOUR
      GROUP BY name
    ) USING (name)
    """

    Sanbase.Clickhouse.Query.put_sql(query_struct, sql)
  end

  def last_balance_before_query(addresses, slug, decimals, blockchain, datetime) do
    sql = """
    SELECT
      address,
      argMax(value, dt) / {{decimals}} AS last_value_before
    FROM (
      SELECT
        address,
        arrayJoin(groupArrayMerge(values)) AS values_merged,
        values_merged.1 AS dt,
        values_merged.2 AS value
      FROM balances_aggregated
      WHERE
        #{address_clause(addresses, argument_name: "addresses")} AND
        blockchain = {{blockchain}} AND
        asset_ref_id = ( SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = {{slug}} LIMIT 1 )
      GROUP BY address, blockchain, asset_ref_id
      HAVING dt < toDateTime({{datetime}})
    )
    GROUP BY address
    """

    params = %{
      addresses: addresses,
      blockchain: blockchain,
      slug: slug,
      datetime: DateTime.to_unix(datetime),
      decimals: Integer.pow(10, decimals)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp address_clause(address, opts) when is_binary(address) do
    arg_name = Keyword.fetch!(opts, :argument_name)
    "address = {{#{arg_name}}}"
  end

  defp address_clause(addresses, opts) when is_list(addresses) do
    arg_name = Keyword.fetch!(opts, :argument_name)
    "address IN ({{#{arg_name}}})"
  end
end
