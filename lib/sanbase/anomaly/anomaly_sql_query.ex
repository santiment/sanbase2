defmodule Sanbase.Anomaly.SqlQuery do
  @table "anomalies"
  @metadata_table "anomalies_model_metadata"

  @moduledoc ~s"""
  Define the SQL queries to access to the anomalies in Clickhouse

  The anomalies are stored in the '#{@table}' clickhouse table
  """

  use Ecto.Schema

  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]
  import Sanbase.Metric.SqlQuery.Helper, only: [aggregation: 3]

  alias Sanbase.Anomaly.FileHandler

  @table_map FileHandler.table_map()
  @metric_map FileHandler.metric_map()
  @model_name_map FileHandler.model_name_map()

  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:value, :float)
    field(:asset_id, :integer)
    field(:metric_id, :integer)
    field(:model_id, :integer)
    field(:computed_at, :utc_datetime)
  end

  def timeseries_data_query(anomaly, slug, from, to, interval, aggregation) do
    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS t,
      toFloat32(#{aggregation(aggregation, "value", "t")})
    FROM(
      SELECT
        dt,
        argMax(value, computed_at) AS value
      FROM #{Map.get(@table_map, anomaly)}
      PREWHERE
        dt >= toDateTime(?2) AND
        dt < toDateTime(?3) AND
        model_id GLOBAL IN (
          SELECT model_id
          FROM #{@metadata_table}
          PREWHERE
            name = ?4 AND
            metric_id = ( SELECT argMax(metric_id, computed_at) AS metric_id FROM metric_metadata PREWHERE name = ?5 ) AND
            asset_id = ( SELECT argMax(asset_id, computed_at) FROM asset_metadata PREWHERE name = ?6 )
          )
      GROUP BY dt
    )
    GROUP BY t
    ORDER BY t
    """

    args = [
      str_to_sec(interval),
      from,
      to,
      Map.get(@model_name_map, anomaly),
      Map.get(@metric_map, anomaly),
      slug
    ]

    {query, args}
  end

  def aggregated_timeseries_data_query(anomaly, asset_ids, from, to, aggregation) do
    query = """
    SELECT
      toUInt32(asset_id),
      toFloat32(#{aggregation(aggregation, "value", "t")})
    FROM(
      SELECT
        dt,
        asset_id,
        argMax(value, computed_at) AS value
      FROM #{Map.get(@table_map, anomaly)}
      PREWHERE
        dt >= toDateTime(?1) AND
        dt < toDateTime(?2) AND
        model_id GLOBAL IN (
          SELECT model_id
          FROM #{@metadata_table}
          PREWHERE
            asset_id IN (?3) AND
            name = ?4 AND
            metric_id = ( SELECT argMax(metric_id, computed_at) AS metric_id FROM metric_metadata PREWHERE name = ?5 )
        )
      GROUP BY dt, asset_id
    )
    GROUP BY asset_id
    """

    args = [
      from,
      to,
      asset_ids,
      Map.get(@model_name_map, anomaly),
      Map.get(@metric_map, anomaly)
    ]

    {query, args}
  end

  def available_slugs_query(anomaly) do
    query = """
    SELECT DISTINCT(name)
    FROM asset_metadata
    PREWHERE asset_id GLOBAL IN (
      SELECT DISTINCT(asset_id)
      FROM #{@metadata_table}
      PREWHERE
        name = ?1 AND
        metric_id = ( SELECT argMax(metric_id, computed_at) FROM metric_metadata PREWHERE name = ?2 a
    )
    """

    args = [
      Map.get(@model_name_map, anomaly),
      Map.get(@metric_map, anomaly)
    ]

    {query, args}
  end

  def available_anomalies_query() do
    query = """
    SELECT name, toUInt32(asset_id), toUInt32(metric_id)
    FROM #{@metadata_table}
    GROUP BY name, asset_id, metric_id
    """

    args = []
    {query, args}
  end

  def first_datetime_query(anomaly, nil) do
    query = """
    SELECT toUnixTimestamp(toDateTime(min(dt)))
    FROM #{@table}
    PREWHERE model_id GLOBAL IN (
      SELECT
        model_id FROM #{@metadata_table}
      PREWHERE
        name = ?1 AND
        metric_id = ( SELECT argMax(metric_id, computed_at) FROM metric_metadata PREWHERE name = ?2 )
    )
    """

    args = [
      Map.get(@model_name_map, anomaly),
      Map.get(@metric_map, anomaly)
    ]

    {query, args}
  end

  def first_datetime_query(anomaly, slug) do
    query = """
    SELECT toUnixTimestamp(toDateTime(min(dt)))
    FROM #{@table}
    PREWHERE model_id GLOBAL IN (
      SELECT
        model_id FROM #{@metadata_table}
      PREWHERE
        name = ?1 AND
        metric_id = ( SELECT argMax(metric_id, computed_at) FROM metric_metadata PREWHERE name = ?2 ) AND
        asset_id = ( SELECT argMax(asset_id, computed_at) FROM asset_metadata PREWHERE name = ?3 )
    )
    """

    args = [
      Map.get(@model_name_map, anomaly),
      Map.get(@metric_map, anomaly),
      slug
    ]

    {query, args}
  end
end
