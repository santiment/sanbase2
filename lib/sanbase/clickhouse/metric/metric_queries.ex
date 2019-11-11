defmodule Sanbase.Clickhouse.Metric.Queries do
  @table "daily_metrics_v2"

  @moduledoc ~s"""
  Define the SQL queries to access to the v2 metrics in Clickhouse

  The metrics are stored in the '#{@table}' clickhouse table where each metric
  is defined by a `metric_id` and every project is defined by an `asset_id`.
  """

  use Ecto.Schema

  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]

  import Sanbase.Clickhouse.Metric.Helper, only: [metric_name_id_map: 0]

  alias Sanbase.Clickhouse.Metric.FileHandler

  @name_to_column_map FileHandler.name_to_column_map()
  @table_map FileHandler.table_map()

  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:asset_id, :integer)
    field(:metric_id, :integer)
    field(:value, :float)
    field(:computed_at, :utc_datetime)
  end

  defp aggregation(:last, value_column, dt_column), do: "argMax(#{value_column}, #{dt_column})"
  defp aggregation(:first, value_column, dt_column), do: "argMin(#{value_column}, #{dt_column})"
  defp aggregation(aggr, value_column, _dt_column), do: "#{aggr}(#{value_column})"

  def timeseries_data_query(metric, slug, from, to, interval, aggregation) do
    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS t,
      #{aggregation(aggregation, "value", "t")}
    FROM(
      SELECT
        dt,
        argMax(value, computed_at) AS value
      FROM #{Map.get(@table_map, metric)}
      PREWHERE
        dt >= toDateTime(?3) AND
        dt < toDateTime(?4) AND
        asset_id = (
          SELECT argMax(asset_id, computed_at)
          FROM asset_metadata
          PREWHERE name = ?5
        ) AND
        metric_id = (
          SELECT
            argMax(metric_id, computed_at) AS metric_id
          FROM
            metric_metadata
          PREWHERE
            name = ?2
        )
      GROUP BY dt
    )
    GROUP BY t
    ORDER BY t
    """

    args = [
      str_to_sec(interval),
      Map.get(@name_to_column_map, metric),
      from,
      to,
      slug
    ]

    {query, args}
  end

  def histogram_data_query(metric, slug, from, to, interval, limit) do
    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(value)), ?5) * ?5) AS t,
      -sum(measure)
    FROM #{Map.get(@table_map, metric)} FINAL
    PREWHERE
      metric_id = (
        SELECT argMax(metric_id, computed_at)
        FROM metric_metadata
        PREWHERE name = ?1
      ) AND
      asset_id = (
        SELECT argMax(asset_id, computed_at)
        FROM asset_metadata
        PREWHERE name = ?2
      ) AND
      dt > toDateTime(?3) AND dt < toDateTime(?4) AND dt != value
    GROUP BY t
    ORDER BY t DESC
    LIMIT ?6
    """

    args = [
      Map.get(@name_to_column_map, metric),
      slug,
      from,
      to,
      interval |> str_to_sec(),
      limit
    ]

    {query, args}
  end

  def aggregated_timeseries_data_query(metric, asset_ids, from, to, aggregation) do
    query = """
    SELECT
      toUInt32(asset_id),
      #{aggregation(aggregation, "value", "t")}
    FROM(
      SELECT
        dt,
        asset_id,
        argMax(value, computed_at) AS value
      FROM #{Map.get(@table_map, metric)}
      PREWHERE
        dt >= toDateTime(?3) AND
        dt < toDateTime(?4) AND
        asset_id IN (?1) AND
        metric_id = ?2
      GROUP BY dt, asset_id
    )
    GROUP BY asset_id
    """

    {:ok, metric_map} = metric_name_id_map()

    args = [
      asset_ids,
      Map.get(metric_map, Map.get(@name_to_column_map, metric)),
      from,
      to
    ]

    {query, args}
  end

  def available_slugs_query() do
    query = """
    SELECT DISTINCT(name) FROM asset_metadata
    """

    args = []

    {query, args}
  end

  def first_datetime_query(metric, nil) do
    query = """
    SELECT
      toUnixTimestamp(toDateTime(min(dt)))
    FROM #{@table}
    PREWHERE
      metric_id = (
        SELECT
          argMax(metric_id, computed_at) AS metric_id
        FROM
          metric_metadata
        PREWHERE
          name = ?1 ) AND
      value > 0
    """

    args = [Map.get(@name_to_column_map, metric)]

    {query, args}
  end

  def first_datetime_query(metric, slug) do
    query = """
    SELECT
      toUnixTimestamp(toDateTime(min(dt)))
    FROM #{@table}
    PREWHERE
      asset_id = (
        SELECT argMax(asset_id, computed_at)
        FROM asset_metadata
        PREWHERE name = ?1
      ) AND metric_id = (
        SELECT
          argMax(metric_id, computed_at) AS metric_id
        FROM
          metric_metadata
        PREWHERE
          name = ?2 ) AND
      value > 0
    """

    args = [slug, Map.get(@name_to_column_map, metric)]

    {query, args}
  end
end
