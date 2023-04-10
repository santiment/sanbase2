defmodule Sanbase.Signal.SqlQuery do
  @table "signals"

  @moduledoc ~s"""
  Define the SQL queries to access the signals in Clickhouse

  The signals are stored in the '#{@table}' Clickhouse table
  """

  use Ecto.Schema

  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]

  import Sanbase.Metric.SqlQuery.Helper,
    only: [aggregation: 3, asset_id_filter: 2, signal_id_filter: 2]

  alias Sanbase.Signal.FileHandler

  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:value, :float)
    field(:asset_id, :integer)
    field(:signal_id, :integer)
    field(:computed_at, :utc_datetime)
  end

  def available_signals_query(slug) do
    sql = """
    SELECT name
    FROM signal_metadata
    PREWHERE signal_id in (
      SELECT DISTINCT(signal_id)
      FROM #{@table}
      INNER JOIN (
        SELECT * FROM asset_metadata FINAL PREWHERE name = {{slug}}
    ) using(asset_id)
    )
    """

    params = %{slug: slug}
    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def available_slugs_query(signal) do
    sql = """
    SELECT DISTINCT(name)
    FROM asset_metadata
    PREWHERE asset_id in (
      SELECT DISTINCT(asset_id)
      FROM #{@table}
      INNER JOIN (
        SELECT * FROM signal_metadata PREWHERE name = {{signal}}
      ) USING(signal_id))
    """

    params = %{
      signal: Map.get(FileHandler.name_to_signal_map(), signal)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def first_datetime_query(signal, slug) do
    sql = """
    SELECT toUnixTimestamp(toDateTime(min(dt)))
    FROM #{@table}
    PREWHERE
      #{signal_id_filter(%{signal: signal}, argument_name: "signal")} AND
      #{asset_id_filter(%{slug: slug}, argument_name: "slug")}
    """

    params = %{
      signal: Map.get(FileHandler.name_to_signal_map(), signal),
      slug: slug
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def raw_data_query(signals, from, to) do
    # Clickhouse does not support multiple joins with using, so there's an extra
    # nesting just for that
    sql = """
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
        #{maybe_filter_signals(signals, argument_name: "signals", trailing_and: true)}
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}}) AND
        isNotNull(value) AND NOT isNaN(value)
    )
    ANY LEFT JOIN (
      SELECT asset_id, name AS slug FROM asset_metadata FINAL
    ) USING asset_id
    """

    params = %{
      from: from |> DateTime.to_unix(),
      to: to |> DateTime.to_unix(),
      signals: signals
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def timeseries_data_query(signal, slug_or_slugs, from, to, _interval, :none) do
    sql = """
    SELECT
      toUnixTimestamp(dt) AS dt,
      value,
      metadata
    FROM #{@table} FINAL
    PREWHERE
      dt >= toDateTime({{from}}) AND
      dt < toDateTime({{to}}) AND
      isNotNull(value) AND NOT isNaN(value) AND
      #{signal_id_filter(%{signal: signal}, argument_name: "signal")} AND
      #{asset_id_filter(%{slug: slug_or_slugs}, argument_name: "slug")}
    ORDER BY dt
    """

    params = %{
      from: from |> DateTime.to_unix(),
      to: to |> DateTime.to_unix(),
      signal: Map.get(FileHandler.name_to_signal_map(), signal),
      slug: slug_or_slugs
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def timeseries_data_query(signal, slug_or_slugs, from, to, interval, aggregation) do
    sql = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), {{interval}}) * {{interval}}) AS t,
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
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}}) AND
        isNotNull(value) AND NOT isNaN(value) AND
        #{asset_id_filter(%{slug: slug_or_slugs}, argument_name: "slug")} AND
        #{signal_id_filter(%{signal: signal}, argument_name: "signal")}
    )
    GROUP BY t
    ORDER BY t
    """

    params = %{
      interval: str_to_sec(interval),
      from: from |> DateTime.to_unix(),
      to: to |> DateTime.to_unix(),
      signal: Map.get(FileHandler.name_to_signal_map(), signal),
      slug: slug_or_slugs
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def aggregated_timeseries_data_query(signal, slug_or_slugs, from, to, aggregation) do
    sql = """
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
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}}) AND
        #{asset_id_filter(%{slug: slug_or_slugs}, argument_name: "slugs")} AND
        #{signal_id_filter(%{signal: signal}, argument_name: "signal")}
    )
    INNER JOIN (
      SELECT asset_id, name
      FROM asset_metadata FINAL
      PREWHERE name IN ({{slugs}})
    ) USING (asset_id)
    GROUP BY slug
    """

    params = %{
      signal: Map.get(FileHandler.name_to_signal_map(), signal),
      from: from |> DateTime.to_unix(),
      to: to |> DateTime.to_unix(),
      slugs: slug_or_slugs |> List.wrap()
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp maybe_filter_signals(:all, _opts), do: ""

  defp maybe_filter_signals([_ | _], opts) do
    argument_name = Keyword.fetch!(opts, :argument_name)
    trailing_and = if Keyword.get(opts, :trailing_and), do: " AND", else: ""

    """
    signal_id IN (
      SELECT argMax(signal_id, version)
      FROM signal_metadata FINAL
      PREWHERE name in ({{#{argument_name}}})
      GROUP BY name
    )
    """ <> trailing_and
  end
end
