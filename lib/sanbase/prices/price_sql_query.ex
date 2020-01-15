defmodule Sanbase.Price.SqlQuery do
  @table "asset_prices"
  @aggregations [:any, :sum, :avg, :min, :max, :last, :first, :median]

  def aggregations(), do: @aggregations

  defp aggregation(:last, value_column, dt_column), do: "argMax(#{value_column}, #{dt_column})"
  defp aggregation(:first, value_column, dt_column), do: "argMin(#{value_column}, #{dt_column})"
  defp aggregation(aggr, value_column, _dt_column), do: "#{aggr}(#{value_column})"

  def timeseries_data_query(slug, from, to, interval, source, aggregation) do
    {from, to, interval, span} = timerange_parameters(from, to, interval)

    query = """
    SELECT time, SUM(price_usd), SUM(price_btc), SUM(marketcap_usd), SUM(volume_usd), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        toUnixTimestamp(intDiv(toUInt32(?5 + number * ?1), ?1) * ?1) AS time,
        toFloat64(0) AS price_usd,
        toFloat64(0) AS price_btc,
        toFloat64(0) AS marketcap_usd,
        toFloat64(0) AS volume_usd,
        toUInt32(0) AS has_changed
      FROM numbers(?2)

      UNION ALL

      SELECT
        toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS time,
        #{aggregation(aggregation, "price_usd", "dt")} AS price_usd,
        #{aggregation(aggregation, "price_btc", "dt")} AS price_btc,
        #{aggregation(aggregation, "marketcap_usd", "dt")} AS marketcap_usd,
        #{aggregation(aggregation, "volume_usd", "dt")} AS volume_usd,
        toUInt32(1) AS has_changed
      FROM #{@table}
      PREWHERE
        slug = cast(?3, 'LowCardinality(String)') AND
        source = cast(?4, 'LowCardinality(String)') AND
        dt >= toDateTime(?5) AND
        dt < toDateTime(?6)
      GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    args = [interval, span, slug, source, from, to]

    {query, args}
  end

  def timeseries_metric_data_query(slug, metric, from, to, interval, source, aggregation) do
    {from, to, interval, span} = timerange_parameters(from, to, interval)

    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS time,
      #{aggregation(aggregation, "#{metric}", "dt")}
    FROM #{@table}
    PREWHERE
      slug = cast(?3, 'LowCardinality(String)') AND
      source = cast(?4, 'LowCardinality(String)') AND
      dt >= toDateTime(?5) AND
      dt < toDateTime(?6)
    GROUP BY time
    ORDER BY time
    """

    args = [interval, span, slug, source, from, to]

    {query, args}
  end

  def aggregated_timeseries_data_query(slugs, from, to, source, opts \\ []) do
    price_aggr = Keyword.get(opts, :price_aggregation, :avg)
    marketcap_aggr = Keyword.get(opts, :marketcap_aggregation, :avg)
    volume_aggr = Keyword.get(opts, :volume_aggregation, :avg)

    query = """
    SELECT slug, SUM(price_usd), SUM(price_btc), SUM(marketcap_usd), SUM(volume_usd), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        arrayJoin([?1]) AS slug,
        toFloat64(0) AS price_usd,
        toFloat64(0) AS price_btc,
        toFloat64(0) AS marketcap_usd,
        toFloat64(0) AS volume_usd,
        toUInt32(0) AS has_changed

      UNION ALL

      SELECT
        cast(slug, 'String') AS slug,
        #{aggregation(price_aggr, "price_usd", "dt")} AS price_usd,
        #{aggregation(price_aggr, "price_btc", "dt")} AS price_btc,
        #{aggregation(marketcap_aggr, "marketcap_usd", "dt")} AS marketcap_usd,
        #{aggregation(volume_aggr, "volume_usd", "dt")} AS volume_usd,
        toUInt32(1) AS has_changed
      FROM #{@table}
        PREWHERE slug IN (?1) AND
        dt >= toDateTime(?2) AND
        dt < toDateTime(?3) AND
        source = cast(?4, 'LowCardinality(String)')
      GROUP BY slug
    )
    GROUP BY slug
    """

    {query,
     [
       slugs,
       from |> DateTime.to_unix(),
       to |> DateTime.to_unix(),
       source
     ]}
  end

  def aggregated_marketcap_and_volume_query(slugs, from, to, source, opts) do
    marketcap_aggr = Keyword.get(opts, :marketcap_aggregation, :avg)
    volume_aggr = Keyword.get(opts, :volume_aggregation, :avg)

    query = """
    SELECT slug, SUM(marketcap_usd), SUM(volume_usd), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        arrayJoin([?1]) AS slug,
        toFloat64(0) AS marketcap_usd,
        toFloat64(0) AS volume_usd,
        toUInt32(0) AS has_changed

      UNION ALL

      SELECT
        cast(slug, 'String') AS slug,
        #{aggregation(marketcap_aggr, "marketcap_usd", "dt")} AS marketcap_usd,
        #{aggregation(volume_aggr, "volume_usd", "dt")} AS volume_usd,
        toUInt32(1) AS has_changed
      FROM #{@table}
      PREWHERE
        slug IN (?1) AND
        dt >= toDateTime(?2) AND
        dt < toDateTime(?3) AND
        source = cast(?4, 'LowCardinality(String)')
      GROUP BY slug
    )
    GROUP BY slug
    """

    {query,
     [
       slugs,
       from |> DateTime.to_unix(),
       to |> DateTime.to_unix(),
       source
     ]}
  end

  def aggregated_metric_timeseries_data_query(slugs, metric, from, to, source, aggregation) do
    query = """
    SELECT slug, SUM(value), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        arrayJoin([?1]) AS slug,
        toFloat64(0) AS value,
        toUInt32(0) AS has_changed

      UNION ALL

      SELECT
        cast(slug, 'String') AS slug,
        #{aggregation(aggregation, "#{metric}", "dt")} AS value,
        toUInt32(1) AS has_changed
      FROM #{@table}
      PREWHERE
        slug IN (?1) AND
        source = cast(?2, 'LowCardinality(String)') AND
        dt >= toDateTime(?3) AND
        dt < toDateTime(?4)
      GROUP BY slug
    )
    GROUP BY slug
    """

    args = [slugs, source, from |> DateTime.to_unix(), to |> DateTime.to_unix()]

    {query, args}
  end

  def ohlc_query(slug, from, to, source) do
    {from, to} = timerange_parameters(from, to)

    query = """
    SELECT
      SUM(open_price), SUM(high_price), SUM(close_price), SUM(low_price), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        arrayJoin([(?1)]) AS slug,
        toFloat64(0) AS open_price,
        toFloat64(0) AS high_price,
        toFloat64(0) AS close_price,
        toFloat64(0) AS low_price,
        toUInt32(0) AS has_changed

      UNION ALL

      SELECT
        cast(slug, 'String') AS slug,
        argMin(price_usd, dt) AS open_price,
        max(price_usd) AS high_price,
        min(price_usd) AS low_price,
        argMax(price_usd, dt) AS close_price,
        toUInt32(1) AS has_changed
      FROM #{@table}
      PREWHERE
        slug = cast(?1, 'LowCardinality(String)') AND
        source = cast(?2, 'LowCardinality(String)') AND
        dt >= toDateTime(?3) AND
        dt < toDateTime(?4)
      GROUP BY slug
    )
    GROUP BY slug
    """

    args = [slug, source, from, to]

    {query, args}
  end

  def timeseries_ohlc_data_query(slug, from, to, interval, source) do
    {from, to, interval, span} = timerange_parameters(from, to, interval)

    query = """
    SELECT
      time, SUM(open_price), SUM(high_price), SUM(close_price), SUM(low_price), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        toUnixTimestamp(intDiv(toUInt32(?5 + number * ?1), ?1) * ?1) AS time,
        toFloat64(0) AS open_price,
        toFloat64(0) AS high_price,
        toFloat64(0) AS close_price,
        toFloat64(0) AS low_price,
        toUInt32(0) AS has_changed
      FROM numbers(?2)

      UNION ALL

      SELECT
        toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
        argMin(price_usd, dt) AS open_price,
        max(price_usd) AS high_price,
        min(price_usd) AS low_price,
        argMax(price_usd, dt) AS close_price,
        toUInt32(1) AS has_changed
      FROM #{@table}
      PREWHERE
        slug = cast(?3, 'LowCardinality(String)') AND
        source = cast(?4, 'LowCardinality(String)') AND
        dt >= toDateTime(?5) AND
        dt < toDateTime(?6)
        GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    args = [interval, span, slug, source, from, to]

    {query, args}
  end

  def combined_marketcap_and_volume_query(slugs, from, to, interval, source) do
    {from, to, interval, span} = timerange_parameters(from, to, interval)

    query = """
    SELECT time,SUM(marketcap_usd), SUM(volume_usd), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        toUnixTimestamp(intDiv(toUInt32(?5 + number * ?1), ?1) * ?1) AS time,
        toFloat64(0) AS marketcap_usd,
        toFloat64(0) AS volume_usd,
        toUInt32(0) AS has_changed
      FROM numbers(?2)

      UNION ALL

      SELECT
        toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS time,
        argMax(marketcap_usd, dt) AS marketcap_usd,
        argMax(volume_usd, dt) AS volume_usd,
        toUInt32(1) AS has_changed
      FROM #{@table}
      PREWHERE
        slug IN (?3) AND
        source = ?4 AND
        dt >= toDateTime(?5) AND
        dt < toDateTime(?6)
      GROUP BY time, slug
    )
    GROUP BY time
    ORDER BY time
    """

    args = [interval, span, slugs, source, from, to]

    {query, args}
  end

  def last_record_before_query(slug, datetime, source) do
    query = """
    SELECT
      price_usd, price_btc, marketcap_usd, volume_usd
    FROM #{@table}
    PREWHERE
      slug = cast(?1, 'LowCardinality(String)') AND
      source = cast(?2, 'LowCardinality(String)') AND
      dt >= toDateTime(?3) AND
      dt <= toDateTime(?4)
    ORDER BY dt DESC
    LIMIT 1
    """

    # Put an artificial lower boundary otherwise the query is too slow
    from = Timex.shift(datetime, days: -30) |> DateTime.to_unix()
    to = datetime |> DateTime.to_unix()
    args = [slug, source, from, to]

    {query, args}
  end

  def first_datetime_query(slug, source) do
    query = """
    SELECT
      toUnixTimestamp(dt)
    FROM #{@table}
    PREWHERE
      slug = cast(?1, 'LowCardinality(String)') AND
      source = cast(?2, 'LowCardinality(String)')
    ORDER BY dt ASC
    LIMIT 1
    """

    args = [slug, source]

    {query, args}
  end

  def available_slugs_query(source) do
    query = """
    SELECT distinct(slug)
    FROM #{@table}
    PREWHERE source = cast(?1, 'LowCardinality(String)')
    """

    args = [source]

    {query, args}
  end

  def slugs_with_volume_over_query(volume, source) do
    datetime = Timex.shift(Timex.now(), days: -1)

    query = """
    SELECT
      distinct(slug)
    FROM #{@table}
    PREWHERE
      dt >= toDateTime(?1) AND
      source = cast(?2, 'LowCardinality(String)') AND
      volume_usd >= ?3
    """

    args = [datetime |> DateTime.to_unix(), source, volume]

    {query, args}
  end

  # Private functions

  defp timerange_parameters(from, to, interval \\ nil)

  defp timerange_parameters(from, to, nil) do
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)

    {from_unix, to_unix}
  end

  defp timerange_parameters(from, to, interval) do
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)
    interval_sec = Sanbase.DateTimeUtils.str_to_sec(interval)
    span = div(to_unix - from_unix, interval_sec) |> max(1)

    {from_unix, to_unix, interval_sec, span}
  end
end
