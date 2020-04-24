defmodule Sanbase.Clickhouse.Metric.SqlQuery do
  @table "daily_metrics_v2"

  @moduledoc ~s"""
  Define the SQL queries to access to the v2 metrics in Clickhouse

  The metrics are stored in the '#{@table}' clickhouse table where each metric
  is defined by a `metric_id` and every project is defined by an `asset_id`.
  """

  use Ecto.Schema

  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]
  import Sanbase.Metric.SqlQuery.Helper, only: [aggregation: 3, generate_comparison_string: 2]

  alias Sanbase.Clickhouse.Metric.FileHandler

  @name_to_metric_map FileHandler.name_to_metric_map()
  @table_map FileHandler.table_map()

  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:asset_id, :integer)
    field(:metric_id, :integer)
    field(:value, :float)
    field(:computed_at, :utc_datetime)
  end

  def timeseries_data_query(metric, slug, from, to, interval, aggregation) do
    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS t,
      #{aggregation(aggregation, "value", "dt")}
    FROM(
      SELECT
        dt,
        argMax(value, computed_at) AS value
      FROM #{Map.get(@table_map, metric)}
      PREWHERE
        #{maybe_convert_to_date(:after, metric, "dt", "toDateTime(?3)")} AND
        #{maybe_convert_to_date(:before, metric, "dt", "toDateTime(?4)")} AND
        asset_id = ( SELECT asset_id FROM asset_metadata FINAL PREWHERE name = ?5 ) AND
        metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = ?2 )
      GROUP BY dt
    )
    GROUP BY t
    ORDER BY t
    """

    args = [
      str_to_sec(interval),
      Map.get(@name_to_metric_map, metric),
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix(),
      slug
    ]

    {query, args}
  end

  def aggregated_timeseries_data_query(metric, asset_ids, from, to, aggregation) do
    query = """
    SELECT
      toUInt32(asset_id),
      #{aggregation(aggregation, "value", "dt")}
    FROM(
      SELECT
        dt,
        asset_id,
        argMax(value, computed_at) AS value
      FROM #{Map.get(@table_map, metric)}
      PREWHERE
        asset_id IN (?1) AND
        metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = ?2 ) AND
        #{maybe_convert_to_date(:after, metric, "dt", "toDateTime(?3)")} AND
        #{maybe_convert_to_date(:before, metric, "dt", "toDateTime(?4)")}
      GROUP BY dt, asset_id
    )
    GROUP BY asset_id
    """

    args = [
      asset_ids,
      # Fetch internal metric name used. Fallback to the same name if missing.
      Map.get(@name_to_metric_map, metric),
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix()
    ]

    {query, args}
  end

  def slugs_by_filter_query(metric, from, to, aggregation, operation, threshold) do
    query = """
    SELECT name AS slug
    FROM (
      SELECT
        asset_id,
        #{aggregation(aggregation, "value", "dt")} AS value
      FROM(
        SELECT
          dt,
          asset_id,
          argMax(value, computed_at) AS value
        FROM #{Map.get(@table_map, metric)}
        PREWHERE
          metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = ?1 ) AND
          #{maybe_convert_to_date(:after, metric, "dt", "toDateTime(?2)")} AND
          #{maybe_convert_to_date(:before, metric, "dt", "toDateTime(?3)")}
        GROUP BY dt, asset_id
      )
      GROUP BY asset_id
    )
    ALL LEFT JOIN
    (
      SELECT asset_id, name
      FROM asset_metadata FINAL
    ) USING (asset_id)
    WHERE value #{generate_comparison_string(operation, threshold)}
    """

    args = [
      # Fetch internal metric name used. Fallback to the same name if missing.
      Map.get(@name_to_metric_map, metric),
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix()
    ]

    {query, args}
  end

  def available_slugs_in_table_query(table) do
    query = """
    SELECT name
    FROM asset_metadata
    PREWHERE asset_id GLOBAL IN (
      SELECT DISTINCT(asset_id) FROM #{table}
    )
    """

    args = []

    {query, args}
  end

  def available_slugs_for_metric_query(metric) do
    query = """
    SELECT name
    FROM asset_metadata
    PREWHERE asset_id in (
      SELECT asset_id
      FROM #{Map.get(@table_map, metric)}
      PREWHERE metric_id = ( SELECT argMax(metric_id, computed_at) FROM metric_metadata PREWHERE name = ?1 )
    )
    """

    args = [Map.get(@name_to_metric_map, metric)]

    {query, args}
  end

  def last_datetime_computed_at_query(metric, slug) do
    query = """
    SELECT toUnixTimestamp(argMax(computed_at, dt))
    FROM #{Map.get(@table_map, metric)} FINAL
    PREWHERE
      metric_id = ( SELECT argMax(metric_id, computed_at) FROM metric_metadata PREWHERE name = ?1 ) AND
      asset_id = ( SELECT argMax(asset_id, computed_at) FROM asset_metadata PREWHERE name = ?2 )
    """

    args = [Map.get(@name_to_metric_map, metric), slug]
    {query, args}
  end

  def first_datetime_query(metric, nil) do
    query = """
    SELECT
      toUnixTimestamp(toDateTime(min(dt)))
    FROM #{Map.get(@table_map, metric)}
    PREWHERE
      metric_id = ( SELECT argMax(metric_id, computed_at) AS metric_id FROM metric_metadata PREWHERE name = ?1 ) AND
      value > 0
    """

    args = [Map.get(@name_to_metric_map, metric)]

    {query, args}
  end

  def first_datetime_query(metric, slug) do
    query = """
    SELECT
      toUnixTimestamp(toDateTime(min(dt)))
    FROM #{Map.get(@table_map, metric)}
    PREWHERE
      asset_id = ( SELECT argMax(asset_id, computed_at) FROM asset_metadata PREWHERE name = ?1 ) AND
      metric_id = ( SELECT argMax(metric_id, computed_at) AS metric_id FROM metric_metadata PREWHERE name = ?2 ) AND
      value > 0
    """

    args = [slug, Map.get(@name_to_metric_map, metric)]

    {query, args}
  end

  def available_metrics_in_table_query(table, slug) do
    query = """
    SELECT distinct(metric_id)
    FROM #{table}
    PREWHERE
      asset_id = ( SELECT argMax(asset_id, computed_at) FROM asset_metadata PREWHERE name = ?1 ) AND
      dt > toDateTime(?2)
    """

    # artifical boundary so the query checks less results
    datetime = Timex.shift(Timex.now(), days: -14) |> DateTime.to_unix()
    args = [slug, datetime]
    {query, args}
  end

  defp maybe_convert_to_date(:after, metric, dt_column, code) do
    case Map.get(@table_map, metric) do
      "daily_metrics_v2" -> "#{dt_column} >= toDate(#{code})"
      _ -> "#{dt_column} >= #{code}"
    end
  end

  defp maybe_convert_to_date(:before, metric, dt_column, code) do
    case Map.get(@table_map, metric) do
      "daily_metrics_v2" -> "#{dt_column} <= toDate(#{code})"
      _ -> "#{dt_column} <= #{code}"
    end
  end
end
