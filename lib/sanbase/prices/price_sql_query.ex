defmodule Sanbase.Price.SqlQuery do
  @table "asset_prices_v3"

  import Sanbase.DateTimeUtils, only: [maybe_str_to_sec: 1]

  import Sanbase.Metric.SqlQuery.Helper,
    only: [
      to_unix_timestamp: 3,
      aggregation: 3,
      generate_comparison_string: 3,
      dt_to_unix: 2,
      timerange_parameters: 2,
      timerange_parameters: 3
    ]

  def timeseries_data_query(slug_or_slugs, from, to, interval, source, aggregation) do
    sql = """
    SELECT
      #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS time,
      #{aggregation(aggregation, "price_usd", "dt")} AS price_usd,
      #{aggregation(aggregation, "price_btc", "dt")} AS price_btc,
      #{aggregation(aggregation, "marketcap_usd", "dt")} AS marketcap_usd,
      #{aggregation(aggregation, "volume_usd", "dt")} AS volume_usd
    FROM #{@table}
    PREWHERE
      #{slug_filter(slug_or_slugs, argument_name: "slug")} AND
      source = cast({{source}}, 'LowCardinality(String)') AND
      dt >= toDateTime({{from}}) AND
      dt < toDateTime({{to}})
    GROUP BY slug, time
    ORDER BY time ASC
    """

    params = %{
      interval: maybe_str_to_sec(interval),
      slug: slug_or_slugs,
      source: source,
      from: dt_to_unix(:from, from),
      to: dt_to_unix(:to, to)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def timeseries_metric_data_query(slug_or_slugs, metric, from, to, interval, source, aggregation) do
    sql = """
    SELECT
      #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS time,
      #{aggregation(aggregation, "#{metric}", "dt")}
    FROM #{@table}
    PREWHERE
      #{slug_filter(slug_or_slugs, argument_name: "slug")} AND
      NOT isNaN(#{metric}) AND isNotNull(#{metric})  AND
      source = cast({{source}}, 'LowCardinality(String)') AND
      dt >= toDateTime({{from}}) AND
      dt < toDateTime({{to}})
    GROUP BY time
    ORDER BY time
    """

    params = %{
      interval: maybe_str_to_sec(interval),
      slug: slug_or_slugs,
      source: source,
      from: dt_to_unix(:from, from),
      to: dt_to_unix(:to, to)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def timeseries_metric_data_per_slug_query(
        slug_or_slugs,
        metric,
        from,
        to,
        interval,
        source,
        aggregation
      ) do
    sql = """
    SELECT
      #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS time,
      slug,
      #{aggregation(aggregation, "#{metric}", "dt")}
    FROM #{@table} FINAL
    PREWHERE
      #{slug_filter(slug_or_slugs, argument_name: "slug")} AND
      source = cast({{source}}, 'LowCardinality(String)') AND
      dt >= toDateTime({{from}}) AND
      dt < toDateTime({{to}})
    GROUP BY time, slug
    ORDER BY time
    """

    params = %{
      interval: maybe_str_to_sec(interval),
      slug: slug_or_slugs,
      source: source,
      from: dt_to_unix(:from, from),
      to: dt_to_unix(:to, to)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def aggregated_timeseries_data_query(slugs, from, to, source, opts \\ []) do
    price_aggr = Keyword.get(opts, :price_aggregation, :avg)
    marketcap_aggr = Keyword.get(opts, :marketcap_aggregation, :avg)
    volume_aggr = Keyword.get(opts, :volume_aggregation, :avg)

    sql = """
    SELECT slugString, SUM(price_usd), SUM(price_btc), SUM(marketcap_usd), SUM(volume_usd), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        arrayJoin([{{slugs}}]) AS slugString,
        toFloat64(0) AS price_usd,
        toFloat64(0) AS price_btc,
        toFloat64(0) AS marketcap_usd,
        toFloat64(0) AS volume_usd,
        toUInt32(0) AS has_changed

      UNION ALL

      SELECT
        cast(slug, 'String') AS slugString,
        #{aggregation(price_aggr, "price_usd", "dt")} AS price_usd,
        #{aggregation(price_aggr, "price_btc", "dt")} AS price_btc,
        #{aggregation(marketcap_aggr, "marketcap_usd", "dt")} AS marketcap_usd,
        #{aggregation(volume_aggr, "volume_usd", "dt")} AS volume_usd,
        toUInt32(1) AS has_changed
      FROM #{@table}
        PREWHERE slug IN ({{slugs}}) AND
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}}) AND
        source = cast({{source}}, 'LowCardinality(String)')
      GROUP BY slug
    )
    GROUP BY slugString
    """

    params = %{
      slugs: slugs,
      from: dt_to_unix(:from, from),
      to: dt_to_unix(:to, to),
      source: source
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def aggregated_marketcap_and_volume_query(slugs, from, to, source, opts) do
    marketcap_aggr = Keyword.get(opts, :marketcap_aggregation, :avg)
    volume_aggr = Keyword.get(opts, :volume_aggregation, :avg)

    sql = """
    SELECT slugString, SUM(marketcap_usd), SUM(volume_usd), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        arrayJoin([{{slugs}}]) AS slugString,
        toFloat64(0) AS marketcap_usd,
        toFloat64(0) AS volume_usd,
        toUInt32(0) AS has_changed

      UNION ALL

      SELECT
        cast(slug, 'String') AS slugString,
        #{aggregation(marketcap_aggr, "marketcap_usd", "dt")} AS marketcap_usd,
        #{aggregation(volume_aggr, "volume_usd", "dt")} AS volume_usd,
        toUInt32(1) AS has_changed
      FROM #{@table}
      PREWHERE
        slug IN ({{slugs}}) AND
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}}) AND
        source = cast({{source}}, 'LowCardinality(String)')
      GROUP BY slug
    )
    GROUP BY slugString
    """

    params = %{
      slugs: slugs,
      from: dt_to_unix(:from, from),
      to: dt_to_unix(:to, to),
      source: source
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def aggregated_metric_timeseries_data_query(slugs, metric, from, to, source, aggregation) do
    sql = """
    SELECT slugString, SUM(value), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        arrayJoin([{{slugs}}]) AS slugString,
        toFloat64(0) AS value,
        toUInt32(0) AS has_changed

      UNION ALL

      SELECT
        cast(slug, 'String') AS slugString,
        #{aggregation(aggregation, "#{metric}", "dt")} AS value,
        toUInt32(1) AS has_changed
      FROM #{@table}
      PREWHERE
        NOT isNaN(#{metric}) AND isNotNull(#{metric}) AND
        slug IN ({{slugs}}) AND
        source = cast({{source}}, 'LowCardinality(String)') AND
        dt < toDateTime({{to}})
        #{if from, do: "AND dt >= toDateTime({{from}})"}
      GROUP BY slug
    )
    GROUP BY slugString
    """

    params = %{
      slugs: slugs,
      from: dt_to_unix(:from, from),
      to: dt_to_unix(:to, to),
      source: source
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def slugs_by_filter_query(metric, from, to, operation, threshold, aggregation, source) do
    query_struct = filter_order_base_query(metric, from, to, aggregation, source)

    sql =
      query_struct.sql <>
        """
        WHERE #{generate_comparison_string("value", operation, threshold)}
        """

    Sanbase.Clickhouse.Query.put_sql(query_struct, sql)
  end

  def slugs_order_query(metric, from, to, direction, aggregation, source) do
    query_struct = filter_order_base_query(metric, from, to, aggregation, source)

    sql =
      query_struct.sql <>
        """
        ORDER BY value #{direction |> Atom.to_string() |> String.upcase()}
        """

    Sanbase.Clickhouse.Query.put_sql(query_struct, sql)
  end

  defp filter_order_base_query(metric, from, to, aggregation, source) do
    # In case of `:last` aggregation, scanning big intervals of data leads to
    # unnecessarily increased resources consumption as we're getting only the
    # last value. We rewrite the `from` parameter to be closer to `to`. This
    # rewrite has negative effect in cases there are lagging values. If the
    # value is lagging more than 7 days, though, it's safe to assume it is not
    # supported.
    from =
      case aggregation do
        :last -> Enum.max([from, Timex.shift(to, days: -7)], DateTime)
        _ -> from
      end

    sql = """
    SELECT slug, value
    FROM (
      SELECT
        slug,
        #{aggregation(aggregation, "#{metric}", "dt")} AS value
      FROM #{@table}
      PREWHERE
        isNotNull(#{metric}) AND NOT isNaN(#{metric}) AND
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}}) AND
        source = cast({{source}}, 'LowCardinality(String)')
      GROUP BY slug
    )
    """

    params = %{
      from: dt_to_unix(:from, from),
      to: dt_to_unix(:to, to),
      source: source
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def ohlc_query(slug, from, to, source) do
    sql = """
    SELECT
      SUM(open_price), SUM(high_price), SUM(close_price), SUM(low_price), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        arrayJoin([({{slug}})]) AS slugString,
        toFloat64(0) AS open_price,
        toFloat64(0) AS high_price,
        toFloat64(0) AS close_price,
        toFloat64(0) AS low_price,
        toUInt32(0) AS has_changed

      UNION ALL

      SELECT
        cast(slug, 'String') AS slugString,
        argMin(price_usd, dt) AS open_price,
        max(price_usd) AS high_price,
        min(price_usd) AS low_price,
        argMax(price_usd, dt) AS close_price,
        toUInt32(1) AS has_changed
      FROM #{@table}
      PREWHERE
        slug = cast({{slug}}, 'LowCardinality(String)') AND
        source = cast({{ource}}, 'LowCardinality(String)') AND
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}})
      GROUP BY slug
    )
    GROUP BY slugString
    """

    {from, to} = timerange_parameters(from, to)

    params = %{
      slug: slug,
      from: from,
      to: to,
      source: source
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def timeseries_ohlc_data_query(slug, from, to, interval, source) do
    sql = """
    SELECT
      #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS time,
      argMin(price_usd, dt) AS open_price,
      max(price_usd) AS high_price,
      min(price_usd) AS low_price,
      argMax(price_usd, dt) AS close_price
    FROM #{@table}
    PREWHERE
      slug = cast({{slug}}, 'LowCardinality(String)') AND
      source = cast({{source}}, 'LowCardinality(String)') AND
      dt >= toDateTime({{from}}) AND
      dt < toDateTime({{to}})
    GROUP BY time
    ORDER BY time ASC
    """

    params = %{
      interval: maybe_str_to_sec(interval),
      slug: slug,
      source: source,
      from: dt_to_unix(:from, from),
      to: dt_to_unix(:to, to)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def combined_marketcap_and_volume_query(slugs, from, to, interval, source) do
    sql = """
    SELECT time,SUM(marketcap_usd), SUM(volume_usd), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        toUnixTimestamp(intDiv(toUInt32({{from}} + number * {{interval}}), {{interval}}) * {{interval}}) AS time,
        toFloat64(0) AS marketcap_usd,
        toFloat64(0) AS volume_usd,
        toUInt32(0) AS has_changed
      FROM numbers({{span}})
      UNION ALL
      SELECT
        #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS time,
        argMax(marketcap_usd, dt) AS marketcap_usd,
        argMax(volume_usd, dt) AS volume_usd,
        toUInt32(1) AS has_changed
      FROM #{@table}
      PREWHERE
        slug IN ({{slugs}}) AND
        source = cast({{source}}, 'LowCardinality(String)') AND
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}})
      GROUP BY time, slug
    )
    GROUP BY time
    ORDER BY time
    """

    {from, to, interval, span} = timerange_parameters(from, to, interval)

    params = %{
      interval: interval,
      slugs: slugs,
      source: source,
      span: span,
      from: from,
      to: to
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def last_record_before_query(slug, datetime, source) do
    sql = """
    SELECT price_usd, price_btc, marketcap_usd, volume_usd
    FROM #{@table}
    WHERE
      slug = cast({{slug}}, 'LowCardinality(String)') AND
      source = cast({{source}}, 'LowCardinality(String)') AND
      dt >= toDateTime({{from}}) AND
      dt < toDateTime({{to}})
    ORDER BY dt DESC
    LIMIT 1
    """

    # Put an artificial lower boundary otherwise the query is too slow
    from = Timex.shift(datetime, days: -30)
    to = datetime

    params = %{
      slug: slug,
      source: source,
      from: dt_to_unix(:from, from),
      to: dt_to_unix(:to, to)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def last_datetime_computed_at_query(slug) do
    sql = """
    SELECT toUnixTimestamp(max(dt))
    FROM #{@table}
    PREWHERE slug = cast({{slug}}, 'LowCardinality(String)')
    """

    params = %{slug: slug}

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def select_any_record_query(slug) do
    sql = """
    SELECT any(dt)
    FROM #{@table}
    PREWHERE slug = cast({{slug}}, 'LowCardinality(String)')
    """

    params = %{slug: slug}

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def first_datetime_query(slug, source) do
    sql = """
    SELECT
      toUnixTimestamp(dt)
    FROM #{@table}
    PREWHERE
      slug = cast({{slug}}, 'LowCardinality(String)') AND
      source = cast({{source}}, 'LowCardinality(String)')
    ORDER BY dt ASC
    LIMIT 1
    """

    params = %{slug: slug, source: source}

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def available_slugs_query(source) do
    sql = """
    SELECT distinct(slug)
    FROM #{@table}
    PREWHERE source = cast({{source}}, 'LowCardinality(String)')
    """

    params = %{source: source}

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def slugs_with_volume_over_query(volume, source) do
    sql = """
    SELECT
      distinct(slug)
    FROM #{@table}
    PREWHERE
      dt >= toDateTime({{datetime}}) AND
      source = cast({{source}}, 'LowCardinality(String)') AND
      volume_usd >= {{volume_usd}}
    """

    params = %{
      datetime: DateTime.add(DateTime.utc_now(), -1, :day),
      volume_usd: volume,
      source: source
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def latest_prices_per_slug_query(slugs, source, limit_per_slug) do
    sql = """
    SELECT
      slug,
      arrayReverse(groupArray(price_usd)) AS last_prices_usd,
      arrayReverse(groupArray(price_btc)) AS last_prices_btc
    FROM (
      SELECT slug, price_usd, price_btc
      FROM #{@table}
      WHERE
        dt >= now() - INTERVAL 7 DAY AND
        source = {{source}} AND
        slug IN ({{slugs}})
      ORDER BY dt desc
      LIMIT {{limit_per_slug}} BY slug
    )
    GROUP BY slug

    """

    params = %{slugs: slugs, source: source, limit_per_slug: limit_per_slug}

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  # Private functions

  defp slug_filter(slug, opts) when is_binary(slug) do
    arg_name = Keyword.fetch!(opts, :argument_name)

    """
    slug = cast({{#{arg_name}}}, 'LowCardinality(String)')
    """
  end

  defp slug_filter(slugs, opts) when is_list(slugs) do
    arg_name = Keyword.fetch!(opts, :argument_name)

    """
    slug IN ({{#{arg_name}}})
    """
  end
end
