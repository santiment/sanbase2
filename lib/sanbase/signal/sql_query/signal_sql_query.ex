defmodule Sanbase.Signal.SqlQuery do
  @table "signals"
  @metadata_table "signal_metadata"

  @moduledoc ~s"""
  Define the SQL queries to access the signals in Clickhouse

  The signals are stored in the '#{@table}' Clickhouse table
  """

  use Ecto.Schema

  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]
  import Sanbase.Metric.SqlQuery.Helper, only: [aggregation: 3, asset_id_filter: 2]

  alias Sanbase.Signal.FileHandler

  @name_to_signal_map FileHandler.name_to_signal_map()

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
    PREWHERE signal_id in (
      SELECT DISTINCT(signal_id)
      FROM #{@table}
      INNER JOIN (
        SELECT * FROM asset_metadata FINAL PREWHERE name = ?1
    ) using(asset_id)
    )
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
    PREWHERE asset_id in (
      SELECT DISTINCT(asset_id)
      FROM #{@table}
      INNER JOIN (
        SELECT * FROM #{@metadata_table} PREWHERE name = ?1
      ) USING(signal_id))
    """

    args = [
      Map.get(@name_to_signal_map, signal)
    ]

    {query, args}
  end

  def first_datetime_query(signal, slug) do
    query = """
    SELECT toUnixTimestamp(toDateTime(min(dt)))
    FROM #{@table}
    PREWHERE
      signal_id = ( SELECT argMax(signal_id, version) FROM signal_metadata FINAL PREWHERE name = ?1 GROUP BY name LIMIT 1) AND
      asset_id = ( select asset_id from asset_metadata FINAL PREWHERE name = ?2 LIMIT 1 )
    """

    args = [
      Map.get(@name_to_signal_map, signal),
      slug
    ]

    {query, args}
  end

  def raw_data_query(signals, from, to) do
    # Clickhouse does not support multiple joins with using, so there's an extra
    # nesting just for that

    query = """
    SELECT
      dt, signal, slug, value, metadata
    FROM(
      SELECT
        toUnixTimestamp(dt) AS dt, signal, asset_id, value, metadata, signal_id AS signal_id2
      FROM signals FINAL
      ANY LEFT JOIN (
        SELECT argMax(signal_id, version) AS signal_id2, name AS signal FROM signal_metadata FINAL GROUP BY name
      ) USING signal_id2
      PREWHERE
        #{maybe_filter_signals(signals, argument_position: 3, trailing_and: true)}
        dt >= toDateTime(?1) AND
        dt < toDateTime(?2) AND
        isNotNull(value) AND NOT isNaN(value)
    )
    ANY LEFT JOIN (
      SELECT asset_id, name AS slug FROM asset_metadata FINAL
    ) USING asset_id
    """

    args = [from |> DateTime.to_unix(), to |> DateTime.to_unix()]

    args =
      case signals do
        :all -> args
        [_ | _] -> args ++ [signals]
      end

    {query, args}
  end

  def timeseries_data_query(signal, slug_or_slugs, from, to, _interval, :none) do
    query = """
    SELECT
      toUnixTimestamp(dt) AS dt,
      value,
      metadata
    FROM #{@table} FINAL
    PREWHERE
      dt >= toDateTime(?1) AND
      dt < toDateTime(?2) AND
      isNotNull(value) AND NOT isNaN(value) AND
      signal_id = ( SELECT argMax(signal_id, version) FROM #{@metadata_table} FINAL PREWHERE name = ?3 GROUP BY name LIMIT 1 ) AND
      #{asset_id_filter(%{slug: slug_or_slugs}, argument_position: 4)}
    ORDER BY dt
    """

    args = [
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix(),
      Map.get(@name_to_signal_map, signal),
      slug_or_slugs
    ]

    {query, args}
  end

  def timeseries_data_query(signal, slug_or_slugs, from, to, interval, aggregation) do
    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS t,
      #{aggregation(aggregation, "value", "dt")},
      groupArray(metadata) AS metadata
    FROM(
      SELECT
        asset_id,
        dt,
        value,
        metadata
      FROM #{@table} FINAL
      PREWHERE
        dt >= toDateTime(?2) AND
        dt < toDateTime(?3) AND
        isNotNull(value) AND NOT isNaN(value) AND
        #{asset_id_filter(%{slug: slug_or_slugs}, argument_position: 5)} AND
        signal_id = ( SELECT argMax(signal_id, version) FROM #{@metadata_table} FINAL PREWHERE name = ?4 GROUP BY name LIMIT 1 )
    )
    GROUP BY t
    ORDER BY t
    """

    args = [
      str_to_sec(interval),
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix(),
      Map.get(@name_to_signal_map, signal),
      slug_or_slugs
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
        #{asset_id_filter(%{slug: slug_or_slugs}, argument_position: 4)} AND
        signal_id = ( SELECT argMax(signal_id, version) FROM #{@metadata_table} FINAL PREWHERE name = ?1 GROUP BY name LIMIT 1 )
    )
    INNER JOIN (
      SELECT asset_id, name
      FROM asset_metadata FINAL
      PREWHERE name IN (?4)
    ) USING (asset_id)
    GROUP BY slug
    """

    args = [
      Map.get(@name_to_signal_map, signal),
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix(),
      slug_or_slugs
    ]

    {query, args}
  end

  defp maybe_filter_signals(:all, _opts), do: ""

  defp maybe_filter_signals([_ | _], opts) do
    argument_position = Keyword.fetch!(opts, :argument_position)
    trailing_and = if Keyword.get(opts, :trailing_and), do: " AND", else: ""

    """
    signal_id IN (
      SELECT argMax(signal_id, version)
      FROM signal_metadata FINAL
      PREWHERE name in (?#{argument_position})
      GROUP BY name
    )
    """ <> trailing_and
  end
end
