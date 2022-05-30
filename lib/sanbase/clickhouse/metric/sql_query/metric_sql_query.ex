defmodule Sanbase.Clickhouse.MetricAdapter.SqlQuery do
  @table "daily_metrics_v2"

  @moduledoc ~s"""
  Define the SQL queries to access to the v2 metrics in Clickhouse

  The metrics are stored in the '#{@table}' clickhouse table where each metric
  is defined by a `metric_id` and every project is defined by an `asset_id`.
  """

  use Ecto.Schema

  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]

  import Sanbase.Metric.SqlQuery.Helper,
    only: [
      aggregation: 3,
      generate_comparison_string: 3,
      asset_id_filter: 2,
      additional_filters: 3,
      dt_to_unix: 2
    ]

  alias Sanbase.Clickhouse.MetricAdapter.FileHandler

  @name_to_metric_map FileHandler.name_to_metric_map()
  @table_map FileHandler.table_map()
  @min_interval_map FileHandler.min_interval_map()

  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:asset_id, :integer)
    field(:metric_id, :integer)
    field(:value, :float)
    field(:computed_at, :utc_datetime)
  end

  def timeseries_data_query(metric, selector, from, to, interval, aggregation, filters) do
    asset_filter_value = asset_filter_value(selector)

    args = [
      str_to_sec(interval),
      Map.get(@name_to_metric_map, metric),
      dt_to_unix(:from, from),
      dt_to_unix(:to, to),
      asset_filter_value
    ]

    {additional_filters, args} = additional_filters(filters, args, trailing_and: true)

    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS t,
      #{aggregation(aggregation, "value", "dt")}
    FROM(
      SELECT
        asset_id,
        dt,
        argMax(value, computed_at) AS value
      FROM #{Map.get(@table_map, metric)}
      PREWHERE
        #{additional_filters}
        #{maybe_convert_to_date(:after, metric, "dt", "toDateTime(?3)")} AND
        #{maybe_convert_to_date(:before, metric, "dt", "toDateTime(?4)")} AND
        #{asset_id_filter(selector, argument_position: 5)} AND
        metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = ?2 LIMIT 1 )
        GROUP BY asset_id, metric_id, dt
    )
    WHERE isNotNull(value) AND NOT isNaN(value)
    GROUP BY t
    ORDER BY t
    """

    {query, args}
  end

  def timeseries_data_per_slug_query(
        metric,
        slug_or_slugs,
        from,
        to,
        interval,
        aggregation,
        filters
      ) do
    args = [
      str_to_sec(interval),
      Map.get(@name_to_metric_map, metric),
      dt_to_unix(:from, from),
      dt_to_unix(:to, to),
      slug_or_slugs
    ]

    {additional_filters, args} = additional_filters(filters, args, trailing_and: true)

    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS t,
      name AS slug,
      #{aggregation(aggregation, "value2", "dt")} AS value
    FROM(
      SELECT
        asset_id,
        dt,
        argMax(value, computed_at) AS value2
      FROM #{Map.get(@table_map, metric)}
      PREWHERE
        #{additional_filters}
        #{maybe_convert_to_date(:after, metric, "dt", "toDateTime(?3)")} AND
        #{maybe_convert_to_date(:before, metric, "dt", "toDateTime(?4)")} AND
        isNotNull(value) AND NOT isNaN(value) AND
        #{asset_id_filter(%{slug: slug_or_slugs}, argument_position: 5)} AND
        metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = ?2 LIMIT 1 )
      GROUP BY asset_id, metric_id, dt
    )
    INNER JOIN (
      SELECT asset_id, name
      FROM asset_metadata FINAL
    ) USING (asset_id)
    GROUP BY t, name
    ORDER BY t
    """

    {query, args}
  end

  def aggregated_timeseries_data_query(metric, slugs, from, to, aggregation, filters) do
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

    args = [
      slugs,
      # Fetch internal metric name used. Fallback to the same name if missing.
      Map.get(@name_to_metric_map, metric),
      dt_to_unix(:from, from),
      dt_to_unix(:to, to)
    ]

    {additional_filters, args} = additional_filters(filters, args, trailing_and: true)

    query = """
    SELECT slug, SUM(value), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        arrayJoin([?1]) AS slug,
        toFloat64(0) AS value,
        toUInt32(0) AS has_changed

      UNION ALL

      SELECT
        name AS slug,
        #{aggregation(aggregation, "value", "dt")} AS value,
        toUInt32(1) AS has_changed
      FROM(
        SELECT dt, asset_id, argMax(value, computed_at) AS value
        FROM (
          SELECT dt, asset_id, metric_id, value, computed_at
          FROM #{Map.get(@table_map, metric)}
          PREWHERE
            #{additional_filters}
            #{asset_id_filter(%{slug: slugs}, argument_position: 1)} AND
            metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = ?2 LIMIT 1 ) AND
            isNotNull(value) AND NOT isNaN(value) AND
            #{maybe_convert_to_date(:after, metric, "dt", "toDateTime(?3)")} AND
            #{maybe_convert_to_date(:before, metric, "dt", "toDateTime(?4)")}
          )
          GROUP BY asset_id, metric_id, dt
      )
      INNER JOIN (
        SELECT asset_id, name
        FROM asset_metadata FINAL
      ) USING (asset_id)
      GROUP BY slug
    )
    GROUP BY slug
    """

    {query, args}
  end

  def slugs_by_filter_query(metric, from, to, operation, threshold, aggregation, filters) do
    {query, args} = aggregated_slugs_base_query(metric, from, to, aggregation, filters)

    query =
      query <>
        """
        WHERE #{generate_comparison_string("value", operation, threshold)}
        """

    {query, args}
  end

  def slugs_order_query(metric, from, to, direction, aggregation, filters)
      when direction in [:asc, :desc] do
    {query, args} = aggregated_slugs_base_query(metric, from, to, aggregation, filters)

    query =
      query <>
        """
        ORDER BY value #{direction |> Atom.to_string() |> String.upcase()}
        """

    {query, args}
  end

  defp aggregated_slugs_base_query(metric, from, to, aggregation, filters) do
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

    args = [
      # Fetch internal metric name used. Fallback to the same name if missing.
      Map.get(@name_to_metric_map, metric),
      dt_to_unix(:from, from),
      dt_to_unix(:to, to)
    ]

    {additional_filters, args} = additional_filters(filters, args, trailing_and: true)

    query = """
    SELECT name AS slug, value2 AS value
    FROM (
      SELECT asset_id, #{aggregation(aggregation, "value", "(dt, computed_at)")} AS value2
      FROM #{Map.get(@table_map, metric)}
      PREWHERE
        #{additional_filters}
        metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = ?1 LIMIT 1 ) AND
        isNotNull(value) AND NOT isNaN(value) AND
        #{maybe_convert_to_date(:after, metric, "dt", "toDateTime(?2)")} AND
        #{maybe_convert_to_date(:before, metric, "dt", "toDateTime(?3)")}
      GROUP BY asset_id
    ) AS a
    ALL LEFT JOIN
    (
      SELECT asset_id, name
      FROM asset_metadata FINAL
    ) AS b USING (asset_id)
    """

    {query, args}
  end

  def available_slugs_query() do
    query = """
    SELECT DISTINCT(name)
    FROM asset_metadata FINAL
    PREWHERE
      asset_id GLOBAL IN (
        SELECT DISTINCT(asset_id)
        FROM available_metrics
      )
    """

    args = []

    {query, args}
  end

  def available_slugs_for_metric_query(metric) do
    query = """
    SELECT DISTINCT(name)
    FROM asset_metadata FINAL
    PREWHERE asset_id in (
      SELECT DISTINCT(asset_id)
      FROM available_metrics
      PREWHERE
        metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = ?1 LIMIT 1 ) AND
        end_dt > now() - INTERVAL 14 DAY
    )
    """

    args = [Map.get(@name_to_metric_map, metric)]

    {query, args}
  end

  def last_datetime_computed_at_query(metric, selector) do
    asset_filter_value = asset_filter_value(selector)

    query = """
    SELECT toUnixTimestamp(argMax(computed_at, dt))
    FROM #{Map.get(@table_map, metric)} FINAL
    PREWHERE
      metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = ?1 LIMIT 1 ) AND
      #{asset_id_filter(selector, argument_position: 2)}
    """

    args = [Map.get(@name_to_metric_map, metric), asset_filter_value]
    {query, args}
  end

  def first_datetime_query(metric, nil) do
    query = """
    SELECT
      toUnixTimestamp(start_dt)
    FROM available_metrics FINAL
    PREWHERE
      metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = ?2 LIMIT 1 )
    """

    args = [Map.get(@name_to_metric_map, metric)]

    {query, args}
  end

  def first_datetime_query(metric, selector) do
    asset_filter_value = asset_filter_value(selector)

    query = """
    SELECT
      toUnixTimestamp(argMax(start_dt, computed_at))
    FROM available_metrics
    PREWHERE
      #{asset_id_filter(selector, argument_position: 1)} AND
      metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = ?2 LIMIT 1 )
    GROUP BY asset_id, metric_id
    """

    args = [asset_filter_value, Map.get(@name_to_metric_map, metric)]

    {query, args}
  end

  def available_metrics_for_slug_query(slug) do
    query = """
    SELECT name
    FROM available_metrics FINAL
    INNER JOIN (
      SELECT name, metric_id
      FROM metric_metadata FINAL
    ) USING (metric_id)
    PREWHERE
      #{asset_id_filter(%{slug: slug}, argument_position: 1)} AND
      end_dt > now() - INTERVAL 14 DAY

    """

    args = [slug]
    {query, args}
  end

  # Private functions

  defp maybe_convert_to_date(:after, metric, dt_column, sql_dt_description) do
    table = Map.get(@table_map, metric)
    min_interval = Map.get(@min_interval_map, metric)

    cond do
      String.starts_with?(table, "daily") -> "#{dt_column} >= toDate(#{sql_dt_description})"
      min_interval == "1d" -> "toDate(#{dt_column}) >= toDate(#{sql_dt_description})"
      true -> "#{dt_column} >= #{sql_dt_description}"
    end
  end

  defp maybe_convert_to_date(:before, metric, dt_column, sql_dt_description) do
    table = Map.get(@table_map, metric)
    min_interval = Map.get(@min_interval_map, metric)

    cond do
      String.starts_with?(table, "daily") -> "#{dt_column} <= toDate(#{sql_dt_description})"
      min_interval == "1d" -> "toDate(#{dt_column}) <= toDate(#{sql_dt_description})"
      true -> "#{dt_column} < #{sql_dt_description}"
    end
  end

  defp asset_filter_value(%{slug: slug_or_slugs}), do: slug_or_slugs

  defp asset_filter_value(not_supported),
    do: raise("Got unsupported selector: #{inspect(not_supported)}")
end
