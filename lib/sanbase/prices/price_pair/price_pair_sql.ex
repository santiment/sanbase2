defmodule Sanbase.Price.PricePairSql do
  @table "asset_price_pairs_only"

  import Sanbase.Metric.SqlQuery.Helper,
    only: [
      aggregation: 3,
      generate_comparison_string: 3,
      dt_to_unix: 2,
      timerange_parameters: 2,
      timerange_parameters: 3
    ]

  def timeseries_data_query(
        slug_or_slugs,
        quote_asset,
        from,
        to,
        interval,
        source,
        aggregation
      ) do
    sql = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), {{interval}}) * {{interval}}) AS time,
      #{aggregation(aggregation, "price", "dt")}
    FROM #{@table}
    PREWHERE
      #{slug_filter_map(slug_or_slugs, argument_name: "selector")} AND
      quote_asset = {{quote_asset}} AND
      source = {{source}} AND
      dt >= toDateTime({{from}}) AND
      dt < toDateTime({{to}})
    GROUP BY time
    ORDER BY time
    """

    {from, to, interval, _span} = timerange_parameters(from, to, interval)

    params = %{
      interval: interval,
      selector: slug_or_slugs,
      quote_asset: quote_asset,
      source: source,
      from: from,
      to: to
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def timeseries_data_per_slug_query(
        slugs,
        quote_asset,
        from,
        to,
        interval,
        source,
        aggregation
      ) do
    sql = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), {{interval}}) * {{interval}}) AS time,
      #{base_asset_to_slug()} AS slug,
      #{aggregation(aggregation, "price", "dt")}
    FROM #{@table}
    PREWHERE
      #{slug_filter_map(slugs, argument_name: "selector")} AND
      quote_asset = {{quote_asset}} AND
      source = {{source}} AND
      dt >= toDateTime({{from}}) AND
      dt < toDateTime({{to}})
    GROUP BY time, slug
    ORDER BY time
    """

    {from, to, interval, _span} = timerange_parameters(from, to, interval)

    params = %{
      interval: interval,
      selector: slugs,
      quote_asset: quote_asset,
      source: source,
      from: from,
      to: to
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def aggregated_timeseries_data_query(
        slugs,
        quote_asset,
        from,
        to,
        source,
        aggregation
      ) do
    sql = """
    SELECT slug, SUM(value), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        arrayJoin([{{slugs}}]) AS slug,
        toFloat64(0) AS value,
        toUInt32(0) AS has_changed

      UNION ALL

      SELECT
        -- the cryptocompare_to_san_asset_mapping dict cannot handle multiple assets
        -- having the same cryptocompare slug. Use JOIN instead
        slug,
        #{aggregation(aggregation, "price", "dt")} AS value,
        toUInt32(1) AS has_changed
      FROM #{@table}
      INNER JOIN (
        SELECT base_asset, slug
        FROM san_to_cryptocompare_asset_mapping
        WHERE slug IN ({{slugs}})
      ) USING (base_asset)
      PREWHERE
        #{slug_filter_map(slugs, argument_name: "slugs")} AND
        quote_asset = {{quote_asset}} AND
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}}) AND
        source = {{source}}
      GROUP BY slug
    )
    GROUP BY slug
    """

    {from, to} = timerange_parameters(from, to)

    params = %{
      slugs: slugs,
      quote_asset: quote_asset,
      from: from,
      to: to,
      source: source
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def slugs_by_filter_query(
        quote_asset,
        from,
        to,
        source,
        operation,
        threshold,
        aggregation
      ) do
    query_struct = filter_order_base_query(quote_asset, from, to, source, aggregation)

    sql =
      query_struct.sql <>
        """
        WHERE #{generate_comparison_string("value", operation, threshold)}
        """

    San
    Sanbase.Clickhouse.Query.put_sql(query_struct, sql)
  end

  def slugs_order_query(quote_asset, from, to, source, direction, aggregation) do
    query_struct = filter_order_base_query(quote_asset, from, to, source, aggregation)

    sql =
      query_struct.sql <>
        """
        ORDER BY value #{direction |> Atom.to_string() |> String.upcase()}
        """

    Sanbase.Clickhouse.Query.put_sql(query_struct, sql)
  end

  defp filter_order_base_query(quote_asset, from, to, source, aggregation) do
    sql = """
    SELECT slug, value
    FROM (
      SELECT
        #{base_asset_to_slug()} AS slug,
        value
      FROM (
        SELECT
          base_asset,
          #{aggregation(aggregation, "price", "dt")} AS value
        FROM #{@table}
        WHERE
          isNotNull(price) AND NOT isNaN(price) AND
          quote_asset = {{quote_asset}} AND
          source = {{source}} AND
          dt >= toDateTime({{from}}) AND
          dt < toDateTime({{to}})
        GROUP BY base_asset
      )
      WHERE slug != ''
    )
    """

    params = [
      quote_asset: quote_asset,
      source: source,
      from: from |> DateTime.to_unix(),
      to: to |> DateTime.to_unix()
    ]

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def last_record_before_query(slug, quote_asset, datetime, source) do
    sql = """
    SELECT
      toUnixTimestamp(dt), price
    FROM #{@table}
    WHERE
      #{base_asset_filter(slug, argument_name: "slug")} AND
      quote_asset = {{quote_asset}} AND
      source = {{source}} AND
      dt >= toDateTime({{from}}) AND
      dt < toDateTime({{to}})
    ORDER BY dt DESC
    LIMIT 1
    """

    # Put an artificial lower boundary otherwise the query is too slow
    from = Timex.shift(datetime, days: -14)
    to = datetime

    params = %{
      slug: slug,
      quote_asset: quote_asset,
      source: source,
      from: dt_to_unix(:from, from),
      to: dt_to_unix(:to, to)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def select_any_record_query(slug, quote_asset, source) do
    sql = """
    SELECT any(dt)
    FROM #{@table}
    WHERE
      #{base_asset_filter(slug, argument_name: "slug")} AND
      quote_asset = {{quote_asset}} AND
      source = {{source}}
    """

    params = %{
      slug: slug,
      quote_asset: quote_asset,
      source: source
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def first_datetime_query(slug, quote_asset, source) do
    sql = """
    SELECT
      toUnixTimestamp(dt)
    FROM #{@table}
    WHERE
      #{base_asset_filter(slug, argument_name: "slug")} AND
      quote_asset = {{quote_asset}} AND
      source = {{source}}
    ORDER BY dt ASC
    LIMIT 1
    """

    params = %{
      slug: slug,
      quote_asset: quote_asset,
      source: source
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def last_datetime_computed_at_query(slug, quote_asset, source) do
    sql = """
    SELECT toUnixTimestamp(max(dt))
    FROM #{@table}
    WHERE
      #{base_asset_filter(slug, argument_name: "slug")} AND
      quote_asset = {{quote_asset}} AND
      source = {{source}}
    """

    params = %{
      slug: slug,
      quote_asset: quote_asset,
      source: source
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def available_quote_assets_query(slug, source) do
    sql = """
    SELECT distinct(quote_asset)
    FROM #{@table}
    WHERE
      #{base_asset_filter(slug, argument_name: "slug")} AND
      source = {{source}}
    """

    params = %{
      slug: slug,
      source: source
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def available_slugs_query(source) do
    sql = """
    SELECT #{base_asset_to_slug()} AS slug
    FROM (
      SELECT distinct(base_asset) AS base_asset
      FROM #{@table}
      PREWHERE
        dt >= toDateTime({{datetime}}) AND
        source = {{source}}
    )
    WHERE slug != ''
    """

    params = %{
      datetime: DateTime.add(DateTime.utc_now(), -7, :day) |> DateTime.to_unix(),
      source: source
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def available_slugs_query(quote_asset, source) do
    sql = """
    SELECT #{base_asset_to_slug()} AS slug
    FROM (
      SELECT distinct(base_asset) AS base_asset
      FROM #{@table}
      PREWHERE
        quote_asset = {{quote_asset}} AND
        dt >= toDateTime({{datetime}}) AND
        source = {{source}}
    )
    WHERE slug != ''
    """

    params = %{
      quote_asset: quote_asset,
      datetime: DateTime.add(DateTime.utc_now(), -7, :day) |> DateTime.to_unix(),
      source: source
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  # Private functions

  defp base_asset_filter(slug, opts) when is_binary(slug) do
    arg_name = Keyword.get(opts, :argument_name)

    "base_asset = dictGetString('san_to_cryptocompare_asset_mapping', 'base_asset', tuple({{#{arg_name}}}))"
  end

  defp base_asset_to_slug() do
    "dictGetString('cryptocompare_to_san_asset_mapping', 'slug', tuple(base_asset)) "
  end

  defp slug_filter_map(slug, opts) when is_binary(slug) do
    arg_name = Keyword.fetch!(opts, :argument_name)

    "base_asset = dictGetString('san_to_cryptocompare_asset_mapping', 'base_asset', tuple({{#{arg_name}}}))"
  end

  defp slug_filter_map(slugs, opts) when is_list(slugs) do
    arg_name = Keyword.fetch!(opts, :argument_name)

    # Just using `IN arrayMap(s -> ...)` won't work as the right side of the IN
    # operator is not a constant and Clickhouse throws an error.
    """
    base_asset IN (
      SELECT dictGetString('san_to_cryptocompare_asset_mapping', 'base_asset', tuple(slug)) AS base_asset
      FROM system.one
      ARRAY JOIN [{{#{arg_name}}}] AS slug
      HAVING base_asset != ''
    )
    """
  end
end
