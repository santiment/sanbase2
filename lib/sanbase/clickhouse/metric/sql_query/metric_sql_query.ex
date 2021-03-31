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
    only: [aggregation: 3, generate_comparison_string: 3, asset_id_filter: 2]

  alias Sanbase.Clickhouse.MetricAdapter.FileHandler

  @name_to_metric_map FileHandler.name_to_metric_map()
  @table_map FileHandler.table_map()

  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:asset_id, :integer)
    field(:metric_id, :integer)
    field(:value, :float)
    field(:computed_at, :utc_datetime)
  end

  def timeseries_data_query(metric, slug_or_slugs, from, to, interval, aggregation, filters) do
    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS t,
      #{aggregation(aggregation, "value", "dt")}
    FROM(
      SELECT
        asset_id,
        dt,
        value
      FROM #{Map.get(@table_map, metric)} FINAL
      PREWHERE
        #{additional_filters(filters)}
        #{maybe_convert_to_date(:after, metric, "dt", "toDateTime(?3)")} AND
        #{maybe_convert_to_date(:before, metric, "dt", "toDateTime(?4)")} AND
        isNotNull(value) AND NOT isNaN(value) AND
        #{asset_id_filter(slug_or_slugs, argument_position: 5)} AND
        metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = ?2 LIMIT 1 )
    )
    GROUP BY t
    ORDER BY t
    """

    args = [
      str_to_sec(interval),
      Map.get(@name_to_metric_map, metric),
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix(),
      slug_or_slugs
    ]

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
    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS t,
      name AS slug,
      #{aggregation(aggregation, "value", "dt")} AS value
    FROM(
      SELECT
        asset_id,
        dt,
        value
      FROM #{Map.get(@table_map, metric)} FINAL
      PREWHERE
        #{additional_filters(filters)}
        #{maybe_convert_to_date(:after, metric, "dt", "toDateTime(?3)")} AND
        #{maybe_convert_to_date(:before, metric, "dt", "toDateTime(?4)")} AND
        isNotNull(value) AND NOT isNaN(value) AND
        #{asset_id_filter(slug_or_slugs, argument_position: 5)} AND
        metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = ?2 LIMIT 1 )
    )
    INNER JOIN (
      SELECT asset_id, name
      FROM asset_metadata FINAL
    ) USING (asset_id)
    GROUP BY t, name
    ORDER BY t
    """

    args = [
      str_to_sec(interval),
      Map.get(@name_to_metric_map, metric),
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix(),
      slug_or_slugs
    ]

    {query, args}
  end

  def aggregated_timeseries_data_query(metric, slug_or_slugs, from, to, aggregation, filters) do
    query = """
    SELECT
      name AS slug,
      #{aggregation(aggregation, "value", "dt")}
    FROM(
      SELECT
        dt,
        asset_id,
        value
      FROM #{Map.get(@table_map, metric)} FINAL
      PREWHERE
        #{additional_filters(filters)}
        #{asset_id_filter(slug_or_slugs, argument_position: 1)} AND
        metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = ?2 LIMIT 1 ) AND
        isNotNull(value) AND NOT isNaN(value) AND
        #{maybe_convert_to_date(:after, metric, "dt", "toDateTime(?3)")} AND
        #{maybe_convert_to_date(:before, metric, "dt", "toDateTime(?4)")}
    )
    INNER JOIN (
      SELECT asset_id, name
      FROM asset_metadata FINAL
    ) USING (asset_id)
    GROUP BY slug
    """

    args = [
      slug_or_slugs,
      # Fetch internal metric name used. Fallback to the same name if missing.
      Map.get(@name_to_metric_map, metric),
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix()
    ]

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
        ORDER BY a.value #{direction |> Atom.to_string() |> String.upcase()}
        """

    {query, args}
  end

  defp aggregated_slugs_base_query(metric, from, to, aggregation, filters) do
    query = """
    SELECT name AS slug, value
    FROM (
      SELECT
        asset_id,
        #{aggregation(aggregation, "value", "dt")} AS value
      FROM(
        SELECT
          dt,
          asset_id,
          value
        FROM #{Map.get(@table_map, metric)} FINAL
        PREWHERE
          #{additional_filters(filters)}
          metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = ?1 LIMIT 1 ) AND
          #{maybe_convert_to_date(:after, metric, "dt", "toDateTime(?2)")} AND
          #{maybe_convert_to_date(:before, metric, "dt", "toDateTime(?3)")}
      )
      GROUP BY asset_id
    ) AS a
    ALL LEFT JOIN
    (
      SELECT asset_id, name
      FROM asset_metadata FINAL
    ) AS b USING (asset_id)
    """

    args = [
      # Fetch internal metric name used. Fallback to the same name if missing.
      Map.get(@name_to_metric_map, metric),
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix()
    ]

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

  def last_datetime_computed_at_query(metric, slug) do
    query = """
    SELECT toUnixTimestamp(argMax(computed_at, dt))
    FROM #{Map.get(@table_map, metric)} FINAL
    PREWHERE
      metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = ?1 LIMIT 1 ) AND
      asset_id = ( SELECT asset_id FROM asset_metadata FINAL PREWHERE name = ?2 LIMIT 1 )
    """

    args = [Map.get(@name_to_metric_map, metric), slug]
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

  def first_datetime_query(metric, slug) do
    query = """
    SELECT
      toUnixTimestamp(start_dt)
    FROM available_metrics FINAL
    PREWHERE
      asset_id = ( SELECT asset_id FROM asset_metadata FINAL PREWHERE name = ?1 LIMIT 1 ) AND
      metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = ?2 LIMIT 1 )
    """

    args = [slug, Map.get(@name_to_metric_map, metric)]

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
      asset_id = ( SELECT asset_id FROM asset_metadata FINAL PREWHERE name = ?1 LIMIT 1 ) AND
      end_dt > now() - INTERVAL 14 DAY

    """

    args = [slug]
    {query, args}
  end

  # Private functions

  # Add additional `=` filters to the query. This is mostly used with labeled
  # metrics where additional column filters must be applied.
  defp additional_filters([]), do: []

  defp additional_filters(filters) do
    filters_string =
      filters
      |> Enum.map(fn
        {column, value} when is_binary(value) ->
          "lower(#{column}) = '#{value |> String.downcase()}'"

        {column, value} when is_number(value) ->
          "#{column} = #{value}"
      end)
      |> Enum.join(" AND\n")

    filters_string <> " AND"
  end

  defp maybe_convert_to_date(:after, metric, dt_column, code) do
    case Map.get(@table_map, metric) do
      "daily_" <> _rest_of_table -> "#{dt_column} >= toDate(#{code})"
      _ -> "#{dt_column} >= #{code}"
    end
  end

  defp maybe_convert_to_date(:before, metric, dt_column, code) do
    case Map.get(@table_map, metric) do
      "daily_" <> _rest_of_table -> "#{dt_column} <= toDate(#{code})"
      _ -> "#{dt_column} <= #{code}"
    end
  end
end
