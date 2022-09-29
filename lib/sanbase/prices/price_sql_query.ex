defmodule Sanbase.Price.SqlQuery do
  @table "asset_prices_v3"

  import Sanbase.DateTimeUtils, only: [str_to_sec: 1, maybe_str_to_sec: 1]

  import Sanbase.Metric.SqlQuery.Helper,
    only: [
      to_unix_timestamp: 3,
      aggregation: 3,
      generate_comparison_string: 3,
      dt_to_unix: 2
    ]

  def timeseries_data_query(slug_or_slugs, from, to, interval, source, aggregation) do
    query = """
    SELECT
      #{to_unix_timestamp(interval, "dt", argument_position: 1)} AS time,
      #{aggregation(aggregation, "price_usd", "dt")} AS price_usd,
      #{aggregation(aggregation, "price_btc", "dt")} AS price_btc,
      #{aggregation(aggregation, "marketcap_usd", "dt")} AS marketcap_usd,
      #{aggregation(aggregation, "volume_usd", "dt")} AS volume_usd
    FROM #{@table}
    PREWHERE
      #{slug_filter(slug_or_slugs, argument_position: 2)} AND
      source = cast(?3, 'LowCardinality(String)') AND
      dt >= toDateTime(?4) AND
      dt < toDateTime(?)
    GROUP BY slug, time
    ORDER BY time ASC
    """

    args = [
      maybe_str_to_sec(interval),
      slug_or_slugs,
      source,
      dt_to_unix(:from, from),
      dt_to_unix(:to, to)
    ]

    {query, args}
  end

  def timeseries_metric_data_query(slug_or_slugs, metric, from, to, interval, source, aggregation) do
    query = """
    SELECT
      #{to_unix_timestamp(interval, "dt", argument_position: 1)} AS time,
      #{aggregation(aggregation, "#{metric}", "dt")}
    FROM #{@table}
    PREWHERE
      #{slug_filter(slug_or_slugs, argument_position: 2)} AND
      NOT isNaN(#{metric}) AND isNotNull(#{metric}) AND #{metric} > 0 AND
      source = cast(?3, 'LowCardinality(String)') AND
      dt >= toDateTime(?4) AND
      dt < toDateTime(?5)
    GROUP BY time
    ORDER BY time
    """

    args = [
      maybe_str_to_sec(interval),
      slug_or_slugs,
      source,
      dt_to_unix(:from, from),
      dt_to_unix(:to, to)
    ]

    {query, args}
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
    query = """
    SELECT
      #{to_unix_timestamp(interval, "dt", argument_position: 1)} AS time,
      slug,
      #{aggregation(aggregation, "#{metric}", "dt")}
    FROM #{@table} FINAL
    PREWHERE
      #{slug_filter(slug_or_slugs, argument_position: 2)} AND
      source = cast(?3, 'LowCardinality(String)') AND
      dt >= toDateTime(?4) AND
      dt < toDateTime(?5)
    GROUP BY time, slug
    ORDER BY time
    """

    args = [
      maybe_str_to_sec(interval),
      slug_or_slugs,
      source,
      dt_to_unix(:from, from),
      dt_to_unix(:to, to)
    ]

    {query, args}
  end

  def aggregated_timeseries_data_query(slugs, from, to, source, opts \\ []) do
    price_aggr = Keyword.get(opts, :price_aggregation, :avg)
    marketcap_aggr = Keyword.get(opts, :marketcap_aggregation, :avg)
    volume_aggr = Keyword.get(opts, :volume_aggregation, :avg)

    query = """
    SELECT slugString, SUM(price_usd), SUM(price_btc), SUM(marketcap_usd), SUM(volume_usd), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        arrayJoin([?1]) AS slugString,
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
        PREWHERE slug IN (?1) AND
        dt >= toDateTime(?2) AND
        dt < toDateTime(?3) AND
        source = cast(?4, 'LowCardinality(String)')
      GROUP BY slug
    )
    GROUP BY slugString
    """

    args = [slugs, DateTime.to_unix(from), DateTime.to_unix(to), source]

    {query, args}
  end

  def aggregated_marketcap_and_volume_query(slugs, from, to, source, opts) do
    marketcap_aggr = Keyword.get(opts, :marketcap_aggregation, :avg)
    volume_aggr = Keyword.get(opts, :volume_aggregation, :avg)

    query = """
    SELECT slugString, SUM(marketcap_usd), SUM(volume_usd), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        arrayJoin([?1]) AS slugString,
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
        slug IN (?1) AND
        dt >= toDateTime(?2) AND
        dt < toDateTime(?3) AND
        source = cast(?4, 'LowCardinality(String)')
      GROUP BY slug
    )
    GROUP BY slugString
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
    SELECT slugString, SUM(value), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        arrayJoin([?1]) AS slugString,
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
        slug IN (?1) AND
        source = cast(?2, 'LowCardinality(String)') AND
        dt < toDateTime(?3)
        #{if from, do: "AND dt >= toDateTime(?4)"}
      GROUP BY slug
    )
    GROUP BY slugString
    """

    args =
      case from do
        %DateTime{} -> [slugs, source, to |> DateTime.to_unix(), from |> DateTime.to_unix()]
        _ -> [slugs, source, to |> DateTime.to_unix()]
      end

    {query, args}
  end

  def slugs_by_filter_query(metric, from, to, operation, threshold, aggregation, source) do
    {query, args} = filter_order_base_query(metric, from, to, aggregation, source)

    query =
      query <>
        """
        WHERE #{generate_comparison_string("value", operation, threshold)}
        """

    {query, args}
  end

  def slugs_order_query(metric, from, to, direction, aggregation, source) do
    {query, args} = filter_order_base_query(metric, from, to, aggregation, source)

    query =
      query <>
        """
        ORDER BY value #{direction |> Atom.to_string() |> String.upcase()}
        """

    {query, args}
  end

  defp filter_order_base_query(metric, from, to, aggregation, source) do
    # In case of `:last` aggregation, scanning big intervals of data leads to
    # unnecessarily increased resources consumption as we're getting only the
    # last value. We rewrite the `from` paramter to be closer to `to`. This
    # rewrite has negative effect in cases there are lagging values. If the
    # value is lagging more than 7 days, though, it's safe to assume it is not
    # supported.
    from =
      case aggregation do
        :last -> Enum.max([from, Timex.shift(to, days: -7)], DateTime)
        _ -> from
      end

    query = """
    SELECT slug, value
    FROM (
      SELECT
        slug,
        #{aggregation(aggregation, "#{metric}", "dt")} AS value
      FROM #{@table}
      PREWHERE
        isNotNull(#{metric}) AND NOT isNaN(#{metric}) AND #{metric} > 0 AND
        dt >= toDateTime(?1) AND
        dt < toDateTime(?2) AND
        source = cast(?3, 'LowCardinality(String)')
      GROUP BY slug
    )
    """

    args = [
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix(),
      source
    ]

    {query, args}
  end

  def ohlc_query(slug, from, to, source) do
    {from, to} = timerange_parameters(from, to)

    query = """
    SELECT
      SUM(open_price), SUM(high_price), SUM(close_price), SUM(low_price), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        arrayJoin([(?1)]) AS slugString,
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
        slug = cast(?1, 'LowCardinality(String)') AND
        source = cast(?2, 'LowCardinality(String)') AND
        dt >= toDateTime(?3) AND
        dt < toDateTime(?4)
      GROUP BY slug
    )
    GROUP BY slugString
    """

    args = [slug, source, from, to]

    {query, args}
  end

  def timeseries_ohlc_data_query(slug, from, to, interval, source) do
    query = """
    SELECT
      #{to_unix_timestamp(interval, "dt", argument_position: 1)} AS time,
      argMin(price_usd, dt) AS open_price,
      max(price_usd) AS high_price,
      min(price_usd) AS low_price,
      argMax(price_usd, dt) AS close_price
    FROM #{@table}
    PREWHERE
      slug = cast(?2, 'LowCardinality(String)') AND
      source = cast(?3, 'LowCardinality(String)') AND
      dt >= toDateTime(?4) AND
      dt < toDateTime(?5)
    GROUP BY time
    ORDER BY time ASC
    """

    args = [
      maybe_str_to_sec(interval),
      slug,
      source,
      dt_to_unix(:from, from),
      dt_to_unix(:to, to)
    ]

    {query, args}
  end

  def combined_marketcap_and_volume_query(slugs, from, to, interval, source) do
    query = """
    SELECT
      #{to_unix_timestamp(interval, "dt", argument_position: 1)} AS time,
      argMax(marketcap_usd, dt) AS marketcap_usd,
      argMax(volume_usd, dt) AS volume_usd,
      toUInt32(1) AS has_changed
    FROM #{@table}
    PREWHERE
      slug IN (?2) AND
      source = ?3 AND
      dt >= toDateTime(?4) AND
      dt < toDateTime(?5)
    GROUP BY time, slug
    ORDER BY time, slug ASC
    """

    args = [
      maybe_str_to_sec(interval),
      slugs,
      source,
      dt_to_unix(:from, from),
      dt_to_unix(:to, to)
    ]

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
      dt < toDateTime(?4)
    ORDER BY dt DESC
    LIMIT 1
    """

    # Put an artificial lower boundary otherwise the query is too slow
    from = Timex.shift(datetime, days: -30) |> DateTime.to_unix()
    to = datetime |> DateTime.to_unix()
    args = [slug, source, from, to]

    {query, args}
  end

  def last_datetime_computed_at_query(slug) do
    query = """
    SELECT toUnixTimestamp(max(dt))
    FROM #{@table}
    PREWHERE slug = cast(?1, 'LowCardinality(String)')
    """

    args = [slug]
    {query, args}
  end

  def select_any_record_query(slug) do
    query = """
    SELECT any(dt)
    FROM #{@table}
    PREWHERE slug = cast(?1, 'LowCardinality(String)')
    """

    args = [slug]
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

  def latest_prices_per_slug_query(slugs, limit_per_slug) do
    query = """
    SELECT
      slug,
      arrayReverse(groupArray(price_usd)) AS last_prices_usd,
      arrayReverse(groupArray(price_btc)) AS last_prices_btc
    FROM (
      SELECT slug, price_usd, price_btc
      FROM asset_prices_v3
      PREWHERE dt >= now() - interval 1 week AND slug IN (?1)
      ORDER BY dt desc
      LIMIT ?2 BY slug
    )
    GROUP BY slug

    """

    args = [slugs, limit_per_slug]

    {query, args}
  end

  # Private functions

  defp timerange_parameters(from, to, interval \\ nil)

  defp timerange_parameters(from, to, nil) do
    {dt_to_unix(:from, from), dt_to_unix(:to, to)}
  end

  defp timerange_parameters(from, to, interval) do
    from_unix = dt_to_unix(:from, from)
    to_unix = dt_to_unix(:to, to)
    interval_sec = str_to_sec(interval)
    interval = maybe_str_to_sec(interval)
    span = div(to_unix - from_unix, interval_sec) |> max(1)

    {from_unix, to_unix, interval, span}
  end

  defp slug_filter(slug, opts) when is_binary(slug) do
    arg_position = Keyword.fetch!(opts, :argument_position)

    """
    slug = cast(?#{arg_position}, 'LowCardinality(String)')
    """
  end

  defp slug_filter(slugs, opts) when is_list(slugs) do
    arg_position = Keyword.fetch!(opts, :argument_position)

    """
    slug IN (?#{arg_position})
    """
  end
end
