defmodule Sanbase.Clickhouse.MetricAdapter.SqlQuery do
  @table "daily_metrics_v2"

  @moduledoc ~s"""
  Define the SQL queries to access to the v2 metrics in Clickhouse

  The metrics are stored in the '#{@table}' clickhouse table where each metric
  is defined by a `metric_id` and every project is defined by an `asset_id`.
  """

  use Ecto.Schema

  import Sanbase.DateTimeUtils, only: [maybe_str_to_sec: 1]

  import Sanbase.Metric.SqlQuery.Helper,
    only: [
      to_unix_timestamp: 3,
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
    params = %{
      interval: maybe_str_to_sec(interval),
      metric: Map.get(@name_to_metric_map, metric),
      from: dt_to_unix(:from, from),
      to: dt_to_unix(:to, to),
      selector: asset_filter_value(selector)
    }

    {additional_filters, params} = additional_filters(filters, params, trailing_and: true)

    sql = """
    SELECT
      #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS t,
      #{aggregation(aggregation, "value", "dt")}
    FROM(
      SELECT
        dt,
        argMax(value, computed_at) AS value
      FROM #{Map.get(@table_map, metric)}
      PREWHERE
        #{additional_filters}
        #{maybe_convert_to_date(:after, metric, "dt", "toDateTime({{from}})")} AND
        #{maybe_convert_to_date(:before, metric, "dt", "toDateTime({{to}})")} AND
        #{asset_id_filter(selector, argument_name: "selector", allow_missing_slug: true)} AND
        metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = {{metric}} LIMIT 1 )
        GROUP BY asset_id, dt
    )
    WHERE isNotNull(value) AND NOT isNaN(value)
    GROUP BY t
    ORDER BY t
    """

    Sanbase.Clickhouse.Query.new(sql, params)
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
    params = [
      interval: maybe_str_to_sec(interval),
      metric: Map.get(@name_to_metric_map, metric),
      from: dt_to_unix(:from, from),
      to: dt_to_unix(:to, to),
      selector: slug_or_slugs
    ]

    {additional_filters, params} = additional_filters(filters, params, trailing_and: true)

    sql = """
    SELECT
      #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS t,
      dictGetString('asset_metadata_dict', 'name', asset_id) AS slug,
      #{aggregation(aggregation, "value2", "dt")} AS value
    FROM(
      SELECT
        asset_id,
        dt,
        argMax(value, computed_at) AS value2
      FROM #{Map.get(@table_map, metric)}
      PREWHERE
        #{additional_filters}
        #{maybe_convert_to_date(:after, metric, "dt", "toDateTime({{from}})")} AND
        #{maybe_convert_to_date(:before, metric, "dt", "toDateTime({{to}})")} AND
        isNotNull(value) AND NOT isNaN(value) AND
        #{asset_id_filter(%{slug: slug_or_slugs}, argument_name: "selector")} AND
        metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = {{metric}} LIMIT 1 )
      GROUP BY asset_id, dt
    )
    GROUP BY t, asset_id
    ORDER BY t
    """

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def aggregated_timeseries_data_query(metric, slugs, from, to, aggregation, filters) do
    # In case of `:last` aggregation, scanning big intervals of data leads to
    # unnecessarily increased resources consumption as we're getting only the
    # last value. We rewrite the `from` parameter to be closer to `to`. This
    # rewrite has negative effect in cases there are lagging values. If the
    # value is lagging more than 7 days, though, it's safe to assume it is not
    # supported.
    from =
      case aggregation do
        :last -> Enum.max([from, Timex.shift(to, days: -7)], DateTime)
        _ -> from
      end

    params = %{
      slugs: slugs,
      # Fetch internal metric name used. Fallback to the same name if missing.
      metric: Map.get(@name_to_metric_map, metric),
      from: dt_to_unix(:from, from),
      to: dt_to_unix(:to, to)
    }

    {additional_filters, params} = additional_filters(filters, params, trailing_and: true)

    sql = """
    SELECT slug, SUM(value), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        arrayJoin([{{slugs}}]) AS slug,
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
            #{asset_id_filter(%{slug: slugs}, argument_name: "slugs")} AND
            metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = {{metric}} LIMIT 1 ) AND
            isNotNull(value) AND NOT isNaN(value) AND
            #{maybe_convert_to_date(:after, metric, "dt", "toDateTime({{from}})")} AND
            #{maybe_convert_to_date(:before, metric, "dt", "toDateTime({{to}})")}
          )
          GROUP BY asset_id, dt
      )
      INNER JOIN (
        SELECT asset_id, name
        FROM asset_metadata FINAL
      ) USING (asset_id)
      GROUP BY slug
    )
    GROUP BY slug
    """

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def slugs_by_filter_query(metric, from, to, operation, threshold, aggregation, filters) do
    query_struct = aggregated_slugs_base_query(metric, from, to, aggregation, filters)

    sql =
      query_struct.sql <>
        """
        WHERE #{generate_comparison_string("value", operation, threshold)}
        """

    Sanbase.Clickhouse.Query.put_sql(query_struct, sql)
  end

  def slugs_order_query(metric, from, to, direction, aggregation, filters)
      when direction in [:asc, :desc] do
    query_struct = aggregated_slugs_base_query(metric, from, to, aggregation, filters)

    sql =
      query_struct.sql <>
        """
        ORDER BY value #{direction |> Atom.to_string() |> String.upcase()}
        """

    Sanbase.Clickhouse.Query.put_sql(query_struct, sql)
  end

  defp aggregated_slugs_base_query(metric, from, to, aggregation, filters) do
    # In case of `:last` aggregation, scanning big intervals of data leads to
    # unnecessarily increased resources consumption as we're getting only the
    # last value. We rewrite the `from` parameter to be closer to `to`. This
    # rewrite has negative effect in cases there are lagging values. If the
    # value is lagging more than 7 days, though, it's safe to assume it is not
    # supported.
    from =
      case aggregation do
        :last -> Enum.max([from, Timex.shift(to, days: -7)], DateTime)
        _ -> from
      end

    params = %{
      # Fetch internal metric name used. Fallback to the same name if missing.
      metric: Map.get(@name_to_metric_map, metric),
      from: dt_to_unix(:from, from),
      to: dt_to_unix(:to, to)
    }

    {additional_filters, params} = additional_filters(filters, params, trailing_and: true)

    sql = """
    SELECT
      dictGetString('asset_metadata_dict', 'name', asset_id) AS slug,
      value3 AS value
    FROM (
      SELECT asset_id, #{aggregation(aggregation, "value2", "dt")} AS value3
      FROM (
        SELECT asset_id, dt, argMax(value, computed_at) AS value2
        FROM #{Map.get(@table_map, metric)}
        PREWHERE
          #{additional_filters}
          metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = {{metric}} LIMIT 1 ) AND
          isNotNull(value) AND NOT isNaN(value) AND
          #{maybe_convert_to_date(:after, metric, "dt", "toDateTime({{from}})")} AND
          #{maybe_convert_to_date(:before, metric, "dt", "toDateTime({{to}})")}
        GROUP BY asset_id, dt
      )
      GROUP BY asset_id
    )
    """

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def available_slugs_query() do
    sql = """
    SELECT DISTINCT(name)
    FROM asset_metadata FINAL
    PREWHERE
      asset_id GLOBAL IN (
        SELECT DISTINCT(asset_id)
        FROM available_metrics
      )
    """

    params = %{}

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def available_slugs_for_metric_query(metric) do
    sql = """
    SELECT DISTINCT(name)
    FROM asset_metadata FINAL
    PREWHERE asset_id in (
      SELECT DISTINCT(asset_id)
      FROM available_metrics
      PREWHERE
        metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = {{metric}} LIMIT 1 ) AND
        end_dt > now() - INTERVAL 14 DAY
    )
    """

    params = %{metric: Map.get(@name_to_metric_map, metric)}

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def last_datetime_computed_at_query(metric, selector) do
    sql = """
    SELECT toUnixTimestamp(argMax(computed_at, dt))
    FROM #{Map.get(@table_map, metric)} FINAL
    PREWHERE
      metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = {{metric}} LIMIT 1 ) AND
      #{asset_id_filter(selector, argument_name: "selector")}
    """

    params = %{
      metric: Map.get(@name_to_metric_map, metric),
      selector: asset_filter_value(selector)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def first_datetime_query(metric, nil) do
    sql = """
    SELECT
      toUnixTimestamp(start_dt)
    FROM available_metrics FINAL
    PREWHERE
      metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = {{metric}} LIMIT 1 )
    """

    params = %{metric: Map.get(@name_to_metric_map, metric)}

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def first_datetime_query(metric, selector) do
    sql = """
    SELECT
      toUnixTimestamp(argMax(start_dt, computed_at))
    FROM available_metrics
    PREWHERE
      #{asset_id_filter(selector, argument_name: "selector")} AND
      metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = {{metric}} LIMIT 1 )
    """

    params = %{
      metric: Map.get(@name_to_metric_map, metric),
      selector: asset_filter_value(selector)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def available_metrics_for_selector_query(selector) do
    selector_value =
      case selector do
        %{slug: slug} -> slug
        %{contract_address: contract_address} -> contract_address
      end

    sql = """
    SELECT name
    FROM available_metrics FINAL
    INNER JOIN (
      SELECT name, metric_id
      FROM metric_metadata FINAL
    ) USING (metric_id)
    PREWHERE
      #{asset_id_filter(selector, argument_name: "selector")} AND
      end_dt > now() - INTERVAL 14 DAY

    """

    params = %{selector: selector_value}
    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def available_metrics_for_slug_query(slug) do
    selector = %{slug: slug}

    sql = """
    SELECT name
    FROM available_metrics FINAL
    INNER JOIN (
      SELECT name, metric_id
      FROM metric_metadata FINAL
    ) USING (metric_id)
    PREWHERE
      #{asset_id_filter(selector, argument_name: "selector")} AND
      end_dt > now() - INTERVAL 14 DAY
    """

    params = %{selector: selector}

    Sanbase.Clickhouse.Query.new(sql, params)
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

  defp asset_filter_value(_), do: nil
end
