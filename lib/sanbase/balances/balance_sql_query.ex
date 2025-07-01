defmodule Sanbase.Balance.SqlQuery do
  import Sanbase.Utils.Transform, only: [opts_to_limit_offset: 1]

  import Sanbase.Metric.SqlQuery.Helper,
    only: [generate_comparison_string: 3, timerange_parameters: 3]

  def maybe_selector_clause("ethereum", "ethereum", _slug_key), do: ""

  def maybe_selector_clause("ethereum", _, slug_key) do
    "assetRefId = (SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = {{#{slug_key}}} LIMIT 1) AND"
  end

  def maybe_selector_clause(_, _, _), do: ""

  def decimals("bitcoin", _), do: 1
  def decimals("bitcoin-cash", _), do: 1
  def decimals("litecoin", _), do: 1
  def decimals("dogecoin", _), do: 1
  def decimals(_, decimals), do: Integer.pow(10, decimals)

  def balance_change_query(
        addresses,
        "ethereum" = slug,
        decimals,
        "ethereum" = blockchain,
        from,
        to
      ) do
    sql = """
    WITH
      toDateTime({{from}}) AS from,
      toDateTime({{to}}) AS to,
      ({{addresses}}) AS addresses_of_interest,
      starting_balances AS
      (
          SELECT
              address,
              last_balance_at AS dt,
              balance
          FROM {{yearly_snapshot_table}}
          WHERE (toYear(from) = year) AND (address IN (addresses_of_interest))
      ),
      usual_balances AS
      (
          SELECT
              address,
              dt,
              balance,
              txID,
              computedAt
          FROM {{table}}
          WHERE address IN (addresses_of_interest) AND dt >= toStartOfYear(from) AND dt <= to
      ),
      merged AS
      (
          SELECT
              *,
              '' AS txID,
              dt AS computedAt
          FROM starting_balances
          UNION ALL
          SELECT *
          FROM usual_balances
      )
    SELECT
        address,
        argMaxIf(balance, (dt, txID, computedAt), dt <= from) / {{decimals}} AS start_balance,
        argMaxIf(balance, (dt, txID, computedAt), dt <= to) / {{decimals}} AS end_balance,
        end_balance - start_balance AS diff
    FROM merged
    GROUP BY address;
    """

    params = %{
      addresses: addresses,
      slug: slug,
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to),
      decimals: decimals(blockchain, decimals),
      table: blockchain_to_table_address_ordered(blockchain, slug),
      yearly_snapshot_table: "eth_balance_yearly_snapshots"
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def balance_change_query(addresses, slug, decimals, blockchain, from, to) do
    sql = """
    SELECT
      address,
      argMaxIf(balance, (dt, txID, computedAt), dt <= {{from}}) / {{decimals}} AS start_balance,
      argMaxIf(balance, (dt, txID, computedAt), dt <= {{to}}) / {{decimals}} AS end_balance,
      end_balance - start_balance AS diff
    FROM {{table}}
    WHERE
      #{maybe_selector_clause(blockchain, slug, "slug")}
      #{address_clause(addresses, argument_name: "addresses")} AND
      dt <= {{to}}
    GROUP BY address
    """

    params = %{
      addresses: addresses,
      slug: slug,
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to),
      decimals: decimals(blockchain, decimals),
      table: blockchain_to_table_address_ordered(blockchain, slug)
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
    addresses = List.wrap(address)

    sql = """
    SELECT time, SUM(balance) , SUM(has_changed)
    FROM (
      SELECT
        toUnixTimestamp(intDiv(toUInt32({{from}} + number * {{interval}}), {{interval}}) * {{interval}}) AS time,
        toFloat64(0) AS balance,
        toUInt8(0) AS has_changed
      FROM numbers({{span}})

      UNION ALL

      SELECT
        time,
        SUM(balance) AS balance,
        toUInt8(1) AS has_changed
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(dt), {{interval}}) * {{interval}}) AS time,
          address,
          argMax(balance, (dt, txID, computedAt)) / {{decimals}} AS balance
        FROM {{table}}
        WHERE
          #{maybe_selector_clause(blockchain, slug, "slug")}
          #{address_clause(addresses, argument_name: "addresses")} AND
          dt >= toDateTime({{from}}) AND
          dt <= toDateTime({{to}})
        GROUP BY address, time
      )
      GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    {from, to, interval, span} = timerange_parameters(from, to, interval)

    params = %{
      addresses: addresses,
      slug: slug,
      decimals: decimals(blockchain, decimals),
      from: from,
      to: to,
      interval: interval,
      span: span,
      table: blockchain_to_table_address_ordered(blockchain, slug)
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
    addresses = List.wrap(address)

    sql = """
    SELECT
      time,
      SUM(open) AS open,
      SUM(high) AS high,
      SUM(low) AS low,
      SUM(close) AS close,
      toUInt8(SUM(has_changed))
    FROM (
      SELECT
        toUnixTimestamp(intDiv(toUInt32({{from}} + number * {{interval}}), {{interval}}) * {{interval}}) AS time,
        toFloat64(0) AS open,
        toFloat64(0) AS high,
        toFloat64(0) AS close,
        toFloat64(0) AS low,
        toUInt8(0) AS has_changed
      FROM numbers({{span}})

      UNION ALL

      SELECT
        time,
        SUM(open) AS open,
        SUM(high) AS high,
        SUM(close) AS close,
        SUM(low) AS low,
        toUInt8(1) AS has_changed
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(dt), {{interval}}) * {{interval}}) AS time,
          address,
          argMin(balance, (dt, txID, computedAt)) / {{decimals}} AS open,
          max(balance) / {{decimals}} AS high,
          argMax(balance, (dt, txID, computedAt)) / {{decimals}} AS close,
          min(balance) / {{decimals}} AS low
        FROM {{table}}
        WHERE
          #{maybe_selector_clause(blockchain, slug, "slug")}
          #{address_clause(addresses, argument_name: "addresses")} AND
          dt >= toDateTime({{from}}) AND
          dt <= toDateTime({{to}})
        GROUP BY address, time
      )
      GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    {from, to, interval, span} = timerange_parameters(from, to, interval)

    params = %{
      addresses: addresses,
      slug: slug,
      decimals: decimals(blockchain, decimals),
      from: from,
      to: to,
      interval: interval,
      span: span,
      table: blockchain_to_table_address_ordered(blockchain, slug)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def current_balance_query(addresses, slug, decimals, blockchain, _table) do
    sql = """
    SELECT
      address,
      argMax(balance, (dt, txID, computedAt)) / {{decimals}}
    FROM {{table}}
    WHERE
      #{maybe_selector_clause(blockchain, slug, "slug")}
      #{address_clause(addresses, argument_name: "addresses")}
    GROUP BY address
    """

    params = %{
      addresses: addresses,
      slug: slug,
      decimals: decimals(blockchain, decimals),
      table: blockchain_to_table_address_ordered(blockchain, slug)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def first_datetime_query(address, slug, blockchain) when is_binary(address) do
    sql = """
    SELECT toUnixTimestamp(min(dt))
    FROM {{table}}
    WHERE
      #{maybe_selector_clause(blockchain, slug, "slug")}
      #{address_clause(address, argument_name: "address")}
    """

    params = %{
      address: address,
      slug: slug,
      table: blockchain_to_table_address_ordered(blockchain, slug)
    }

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
      SELECT address, argMax(balance, dt) / {{decimals}} AS balance
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

  def assets_held_by_address_changes_query(address, datetime, table, opts \\ [])

  def assets_held_by_address_changes_query(address, datetime, "erc20_balances" <> _ = table, opts) do
    sql = """
    SELECT
      name,
      greatest(
        argMaxIf(balance, (dt, txID, computedAt), dt <= toDateTime({{datetime}})) / pow(10, decimals),
        0
      ) AS previous_balance,
      greatest(
        argMax(balance, (dt, txID, computedAt)) / pow(10, decimals),
        0
      ) AS current_balance,
      current_balance - previous_balance AS balance_change
    FROM (
      SELECT
        dt,
        address,
        assetRefId AS asset_ref_id,
        balance,
        txID,
        computedAt
      FROM {{table}}
      WHERE
        #{address_clause(address, argument_name: "address")}
    )
    INNER JOIN (
      SELECT asset_ref_id, name, decimals
      FROM asset_metadata FINAL
    ) USING (asset_ref_id)
    GROUP BY address, asset_ref_id, name, decimals
    #{if Keyword.get(opts, :show_assets_with_zero_balance, false), do: "", else: "HAVING balance > 0"}
    """

    params = %{
      address: address,
      table: table,
      datetime: DateTime.to_unix(datetime)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def assets_held_by_address_changes_query(address, datetime, table, opts)
      when table in [
             "eth_balances",
             "btc_balances",
             "bch_balances",
             "ltc_balances",
             "doge_balances"
           ] do
    sql = """
    SELECT
      {{slug}} AS name,
      greatest(
        argMaxIf(balance, (dt, txID, computedAt), dt <= toDateTime({{datetime}})) / {{decimals}},
        0
      ) AS previous_balance,
      greatest(
        argMax(balance, (dt, txID, computedAt)) / {{decimals}},
        0
      ) AS current_balance,
      current_balance - previous_balance AS balance_change
    FROM {{table}}
    WHERE
      #{address_clause(address, argument_name: "address")}
    #{if Keyword.get(opts, :show_assets_with_zero_balance, false), do: "", else: "HAVING balance > 0"}
    """

    params = %{
      decimals: decimals(table_to_slug(table), 18),
      slug: table_to_slug(table),
      address: address,
      table: table,
      datetime: DateTime.to_unix(datetime)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def assets_held_by_address_query(address, table, opts \\ [])

  def assets_held_by_address_query(address, "erc20_balances" <> _ = table, opts) do
    sql = """
    SELECT
      name,
      argMax(balance, (dt, txID, computedAt)) / pow(10, decimals) AS balance
    FROM (
      SELECT
        dt,
        address,
        assetRefId AS asset_ref_id,
        balance,
        txID,
        computedAt
      FROM {{table}}
      WHERE
        #{address_clause(address, argument_name: "address")}
    )
    INNER JOIN (
      SELECT asset_ref_id, name, decimals
      FROM asset_metadata FINAL
    ) USING (asset_ref_id)
    GROUP BY address, asset_ref_id, name, decimals
    #{if Keyword.get(opts, :show_assets_with_zero_balance, false), do: "", else: "HAVING balance > 0"}
    """

    params = %{address: address, table: table}

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def assets_held_by_address_query(address, table, opts)
      when table in [
             "eth_balances",
             "btc_balances",
             "bch_balances",
             "ltc_balances",
             "doge_balances"
           ] do
    # These tables hold info for only 1 asset
    sql = """
    SELECT
      {{slug}} AS name,
      argMax(balance, (dt, txID, computedAt)) / {{decimals}} AS balance
    FROM {{table}}
    WHERE
      #{address_clause(address, argument_name: "address")}
    #{if Keyword.get(opts, :show_assets_with_zero_balance, false), do: "", else: "HAVING balance > 0"}
    """

    params = %{
      decimals: decimals(table_to_slug(table), 18),
      slug: table_to_slug(table),
      table: table,
      address: address
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def usd_value_address_change_query(address, datetime, table, opts \\ [])

  def usd_value_address_change_query(address, datetime, table, opts) do
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

    # The params are already in the query_struct
    Sanbase.Clickhouse.Query.put_sql(query_struct, sql)
  end

  def usd_value_held_by_address_query(address, table, opts \\ [])

  def usd_value_held_by_address_query(address, table, opts) do
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
      argMaxIf(balance, (dt, txID, computedAt), dt <= {{datetime}}) / {{decimals}}
    FROM {{table}}
    WHERE
      #{maybe_selector_clause(blockchain, slug, "slug")}
      #{address_clause(addresses, argument_name: "addresses")} AND
      dt <= toDateTime({{datetime}})
    GROUP BY address
    """

    params = %{
      addresses: addresses,
      slug: slug,
      decimals: decimals(blockchain, decimals),
      datetime: DateTime.to_unix(datetime),
      table: blockchain_to_table_address_ordered(blockchain, slug)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp address_clause(address, opts) when is_binary(address) do
    arg_name = Keyword.fetch!(opts, :argument_name)
    "address = {{#{arg_name}}}"
  end

  defp address_clause([address], opts) when is_binary(address) do
    arg_name = Keyword.fetch!(opts, :argument_name)
    "address = {{#{arg_name}}}"
  end

  defp address_clause(addresses, opts) when is_list(addresses) do
    arg_name = Keyword.fetch!(opts, :argument_name)
    "address IN ({{#{arg_name}}})"
  end

  defp blockchain_to_table_address_ordered(blockchain, slug) do
    case blockchain do
      "ethereum" -> if slug == "ethereum", do: "eth_balances", else: "erc20_balances_address"
      "bitcoin" -> "btc_balances"
      "litecoin" -> "ltc_balances"
      "dogecoin" -> "doge_balances"
      "bitcoin-cash" -> "bch_balances"
      "binance" -> "bep20_balances"
      "xrp" -> "xrp_balances"
    end
  end

  defp table_to_slug(table) do
    case table do
      "eth_balances" -> "ethereum"
      "btc_balances" -> "bitcoin"
      "ltc_balances" -> "litecoin"
      "doge_balances" -> "dogecoin"
      "bch_balances" -> "bitcoin-cash"
    end
  end
end
