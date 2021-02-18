defmodule Sanbase.Signal.SqlQuery do
  @table "signals"
  @metadata_table "signal_metadata"

  @moduledoc ~s"""
  Define the SQL queries to access the signals in Clickhouse

  The signals are stored in the '#{@table}' Clickhouse table
  """

  use Ecto.Schema
  use Absinthe.Schema.Notation, only: [arg: 2]

  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]
  import Sanbase.Metric.SqlQuery.Helper, only: [aggregation: 3, asset_id_filter: 2]

  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:value, :float)
    field(:asset_id, :integer)
    field(:signal_id, :integer)
    field(:computed_at, :utc_datetime)
  end

  def available_signals_query(slug) do
    query = """
    SELECT name
    FROM #{@metadata_table}
    PREWHERE
      name = ?1
    GROUP BY name
    """

    args = [
      slug
    ]

    {query, args}
  end

  def available_slugs_query(signal) do
    query = """
    SELECT DISTINCT(name)
    FROM asset_metadata
    WHERE asset_id in (
      SELECT DISTINCT(asset_id)
      FROM #{@table}
      INNER JOIN (
        SELECT * FROM #{@metadata_table} WHERE name = ?1
      ) USING(signal_id))
    """

    args = [
      signal
    ]

    {query, args}
  end

  def first_datetime_query(signal, slug) do
    query = """
    SELECT toUnixTimestamp(toDateTime(min(dt)))
    FROM #{@table}
    PREWHERE
      signal_id = ( SELECT signal_id FROM signal_metadata FINAL PREWHERE name = ?1 LIMIT 1 ) AND
      asset_id = ( select asset_id from asset_metadata final where name = ?2 LIMIT 1 )
    """

    args = [
      signal,
      slug
    ]

    {query, args}
  end

  def timeseries_data_query(signal, slug, from, to, interval, aggregation) do
    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS t,
      #{aggregation(aggregation, "value", "dt")}
    FROM(
      SELECT
        asset_id,
        dt,
        value
      FROM #{@table} FINAL
      PREWHERE
        dt >= toDateTime(?2) AND
        dt < toDateTime(?3) AND
        isNotNull(value) AND NOT isNaN(value) AND
        signal_id = ( SELECT signal_id FROM #{@metadata_table} FINAL PREWHERE name = ?4 LIMIT 1 ) AND
        asset_id = ( SELECT asset_id FROM asset_metadata FINAL PREWHERE name = ?5 LIMIT 1 )
    )
    GROUP BY t
    ORDER BY t
    """

    args = [
      str_to_sec(interval),
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix(),
      signal,
      slug
    ]

    {query, args}
  end

  def aggregated_timeseries_data_query(signal, slug_or_slugs, from, to, aggregation) do
    query = """
    SELECT
      name as slug,
      toFloat32(#{aggregation(aggregation, "value", "dt")}) as value
    FROM(
      SELECT
        dt,
        asset_id,
        value
      FROM #{@table}
      PREWHERE
        dt >= toDateTime(?2) AND
        dt < toDateTime(?3) AND
        #{asset_id_filter(slug_or_slugs, argument_position: 4)} AND
        signal_id = ( SELECT signal_id FROM #{@metadata_table} FINAL PREWHERE name = ?1 LIMIT 1 )
    )
    INNER JOIN (
      SELECT asset_id, name
      FROM asset_metadata FINAL
      PREWHERE name IN (?4)
    ) USING (asset_id)
    GROUP BY slug
    """

    args = [
      signal,
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix(),
      slug_or_slugs
    ]

    {query, args}
  end
end
