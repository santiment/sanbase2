defmodule Sanbase.Price.PricePairSql do
  @table "asset_price_pairs_only"

  import Sanbase.Metric.SqlQuery.Helper, only: [aggregation: 3, generate_comparison_string: 3]

  def timeseries_data_query(slug_or_slugs, quote_asset, from, to, interval, source, aggregation) do
    {from, to, interval, _span} = timerange_parameters(from, to, interval)

    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS time,
      #{aggregation(aggregation, "price", "dt")}
    FROM #{@table}
    PREWHERE
      #{slug_filter_map(slug_or_slugs, argument_position: 2)} AND
      quote_asset = ?3 AND
      source = ?4 AND
      dt >= toDateTime(?5) AND
      dt < toDateTime(?6)
    GROUP BY time
    ORDER BY time
    """

    args = [interval, slug_or_slugs, quote_asset, source, from, to]

    {query, args}
  end

  def timeseries_data_per_slug_query(slugs, quote_asset, from, to, interval, source, aggregation) do
    {from, to, interval, _span} = timerange_parameters(from, to, interval)

    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS time,
      dictGetString('cryptocompare_to_san_asset_mapping', 'slug', tuple(base_asset)) AS slug,
      #{aggregation(aggregation, "price", "dt")}
    FROM #{@table}
    PREWHERE
      #{slug_filter_map(slugs, argument_position: 2)} AND
      quote_asset = ?3 AND
      source = ?4 AND
      dt >= toDateTime(?5) AND
      dt < toDateTime(?6)
    GROUP BY time, slug
    ORDER BY time
    """

    args = [interval, slugs, quote_asset, source, from, to]

    {query, args}
  end

  def aggregated_timeseries_data_query(slugs, quote_asset, from, to, source, aggregation) do
    query = """
    SELECT slug, SUM(value), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        arrayJoin([?1]) AS slug,
        toFloat64(0) AS value,
        toUInt32(0) AS has_changed

      UNION ALL

      SELECT
        dictGetString('cryptocompare_to_san_asset_mapping', 'slug', tuple(base_asset)) AS slug,
        #{aggregation(aggregation, "price", "dt")} AS value,
        toUInt32(1) AS has_changed

      FROM #{@table}
        PREWHERE
          #{slug_filter_map(slugs, argument_position: 1)} AND
          quote_asset = ?2 AND
          dt >= toDateTime(?3) AND
          dt < toDateTime(?4) AND
          source = ?5
      GROUP BY slug
    )
    GROUP BY slug
    """

    {from, to} = timerange_parameters(from, to)

    args = [slugs, quote_asset, from, to, source]

    {query, args}
  end

  def slugs_by_filter_query(quote_asset, from, to, source, operation, threshold, aggregation) do
    {query, args} = filter_order_base_query(quote_asset, from, to, source, aggregation)

    query =
      query <>
        """
        WHERE #{generate_comparison_string("value", operation, threshold)}
        """

    {query, args}
  end

  def slugs_order_query(quote_asset, from, to, source, direction, aggregation) do
    {query, args} = filter_order_base_query(quote_asset, from, to, source, aggregation)

    query =
      query <>
        """
        ORDER BY value #{direction |> Atom.to_string() |> String.upcase()}
        """

    {query, args}
  end

  defp filter_order_base_query(quote_asset, from, to, source, aggregation) do
    query = """
    SELECT slug, value
    FROM (
      SELECT
        dictGetString('cryptocompare_to_san_asset_mapping', 'slug', tuple(base_asset)) AS slug,
        value
      FROM (
        SELECT
          base_asset,
          #{aggregation(aggregation, "price", "dt")} AS value
        FROM #{@table}
        PREWHERE
          isNotNull(price) AND NOT isNaN(price) AND
          quote_asset = ?1 AND
          source = ?2 AND
          dt >= toDateTime(?3) AND
          dt < toDateTime(?4)
        GROUP BY base_asset
      )
      WHERE slug != ''
    )
    """

    args = [
      quote_asset,
      source,
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix()
    ]

    {query, args}
  end

  def last_record_before_query(slug, quote_asset, datetime, source) do
    query = """
    SELECT
      toUnixTimestamp(dt), price
    FROM #{@table}
    PREWHERE
      base_asset = dictGetString('san_to_cryptocompare_asset_mapping', 'base_asset', tuple(?1)) AND
      quote_asset = ?2 AND
      source = ?3 AND
      dt >= toDateTime(?4) AND
      dt < toDateTime(?5)
    ORDER BY dt DESC
    LIMIT 1
    """

    # Put an artificial lower boundary otherwise the query is too slow
    from = Timex.shift(datetime, days: -14) |> DateTime.to_unix()
    to = datetime |> DateTime.to_unix()
    args = [slug, quote_asset, source, from, to]

    {query, args}
  end

  def select_any_record_query(slug, quote_asset, source) do
    query = """
    SELECT any(dt)
    FROM #{@table}
    PREWHERE
      base_asset = dictGetString('san_to_cryptocompare_asset_mapping', 'base_asset', tuple(?1)) AND
      quote_asset = ?2 AND
      source = ?3
    """

    args = [slug, quote_asset, source]
    {query, args}
  end

  def first_datetime_query(slug, quote_asset, source) do
    query = """
    SELECT
      toUnixTimestamp(dt)
    FROM #{@table}
    PREWHERE
      base_asset = dictGetString('san_to_cryptocompare_asset_mapping', 'base_asset', tuple(?1)) AND
      quote_asset = ?2 AND
      source = ?3
    ORDER BY dt ASC
    LIMIT 1
    """

    args = [slug, quote_asset, source]

    {query, args}
  end

  def available_quote_assets_query(slug, source) do
    query = """
    SELECT distinct(quote_asset)
    FROM #{@table}
    PREWHERE
      base_asset = dictGetString('san_to_cryptocompare_asset_mapping', 'base_asset', tuple(?1)) AND
      source = ?2
    """

    args = [slug, source]

    {query, args}
  end

  def available_slugs_query(source) do
    query = """
    SELECT dictGetString('cryptocompare_to_san_asset_mapping', 'slug', tuple(base_asset)) AS slug
    FROM (
      SELECT distinct(base_asset) AS base_asset
      FROM #{@table}
      PREWHERE
        dt >= toDateTime(?1) AND
        source = ?3
    )
    WHERE slug != ''
    """

    datetime = Timex.shift(Timex.now(), days: -7) |> DateTime.to_unix()

    args = [datetime, source]

    {query, args}
  end

  def available_slugs_query(quote_asset, source, days \\ 7) do
    query = """
    SELECT dictGetString('cryptocompare_to_san_asset_mapping', 'slug', tuple(base_asset)) AS slug
    FROM (
      SELECT distinct(base_asset) AS base_asset
      FROM #{@table}
      PREWHERE
        quote_asset = ?1 AND
        dt >= toDateTime(?2) AND
        source = ?3
    )
    WHERE slug != ''
    """

    datetime = Timex.shift(Timex.now(), days: -days) |> DateTime.to_unix()

    args = [quote_asset, datetime, source]

    {query, args}
  end

  # Private functions

  defp slug_filter_map(slug, opts) when is_binary(slug) do
    pos = Keyword.fetch!(opts, :argument_position)

    "base_asset = dictGetString('san_to_cryptocompare_asset_mapping', 'base_asset', tuple(?#{pos}))"
  end

  defp slug_filter_map(slugs, opts) when is_list(slugs) do
    pos = Keyword.fetch!(opts, :argument_position)

    # Just using `IN arrayMap(s -> ...)` won't work as the right side of the IN
    # operator is not a constant and Clickhouse throws an error.
    """
    base_asset IN (
      SELECT dictGetString('san_to_cryptocompare_asset_mapping', 'base_asset', tuple(slug)) AS base_asset
      FROM system.one
      ARRAY JOIN [?#{pos}] AS slug
      HAVING base_asset != ''
    )
    """
  end

  defp timerange_parameters(from, to, interval \\ nil)

  defp timerange_parameters(from, to, nil) do
    to = Enum.min_by([to, Timex.now()], &DateTime.to_unix/1)
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
