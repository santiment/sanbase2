defmodule Sanbase.Clickhouse.MetricAdapter.LabeledBalanceSqlQuery do
  @moduledoc ~s"""
  SQL queries for `combined_labeled_balance` computed from the
  `combined_labeled_balance_delta` metric through the `default.cumulative_labeled_balance`
  parameterized view.

  The view returns one running balance series per `(asset_id, label_id)` pair, summed from
  the beginning of the history. The last balance before `from_dt` is returned with
  `dt = from_dt`, so labels without changes in the time range still have a value.

  The view parameters cannot be subqueries, so the asset, label and metric ids are resolved
  beforehand with `ids_query/3`.

  The view has rows only when the balance changes. The timeseries queries return every
  interval in the time range, with `has_changed = 0` for the intervals without rows, so
  they can be filled with the last balance (see `LabeledBalance.fill_gaps/1`).
  """

  import Sanbase.Utils.DateTime, only: [maybe_str_to_sec: 1]

  import Sanbase.Metric.SqlQuery.Helper,
    only: [
      to_unix_timestamp: 3,
      to_unix_timestamp_from_number: 2,
      aggregation: 3,
      dt_to_unix: 2,
      timerange_parameters: 3
    ]

  @delta_metric "combined_labeled_balance_delta"

  def ids_query(slugs, label_fqns, version) do
    sql = """
    SELECT 'metric' AS kind, name, toUInt64(metric_id), ''
    FROM metric_metadata_external FINAL
    WHERE name = {{metric}} AND version = {{version}}

    UNION ALL

    SELECT 'asset' AS kind, name, toUInt64(asset_id), ''
    FROM asset_metadata FINAL
    WHERE name IN ({{slugs}})

    UNION ALL

    SELECT DISTINCT 'label' AS kind, fqn, toUInt64(label_id), ifNull(asset_name, '')
    FROM label_metadata
    WHERE fqn IN ({{label_fqns}})
    """

    params = %{
      metric: @delta_metric,
      version: version,
      slugs: slugs,
      label_fqns: label_fqns
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def timeseries_data_query(ids, from, to, interval, aggregation) do
    params = timeseries_params(ids, from, to, interval)
    columns = value_columns(aggregation)

    sql = """
    SELECT t, #{Enum.map_join(columns, ", ", &"SUM(#{&1})")}, max(has_changed)
    FROM (
      SELECT
        #{to_unix_timestamp_from_number(interval, from_argument_name: "from")} AS t,
        #{Enum.map_join(columns, ", ", &"toFloat64(0) AS #{&1}")},
        toUInt8(0) AS has_changed
      FROM numbers({{span}})
      WHERE t < {{to}}

      UNION ALL

      SELECT
        #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS t,
        #{aggregation_columns(aggregation)},
        toUInt8(1) AS has_changed
      FROM #{view_call()}
      #{pairs_filter(ids)}
      GROUP BY t
    )
    GROUP BY t
    ORDER BY t
    """

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def timeseries_data_per_slug_query(ids, from, to, interval, aggregation) do
    params = timeseries_params(ids, from, to, interval)

    sql = """
    SELECT
      t,
      dictGetString('asset_metadata_dict', 'name', asset_id) AS slug,
      SUM(value),
      max(has_changed)
    FROM (
      SELECT
        #{to_unix_timestamp_from_number(interval, from_argument_name: "from")} AS t,
        arrayJoin({{asset_ids:Array(UInt64)}}) AS asset_id,
        toFloat64(0) AS value,
        toUInt8(0) AS has_changed
      FROM numbers({{span}})
      WHERE t < {{to}}

      UNION ALL

      SELECT
        #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS t,
        assumeNotNull(asset_id) AS asset_id,
        #{aggregation(aggregation, "combined_labeled_balance", "dt")} AS value,
        toUInt8(1) AS has_changed
      FROM #{view_call()}
      #{pairs_filter(ids)}
      GROUP BY t, asset_id
    )
    GROUP BY t, asset_id
    ORDER BY asset_id, t
    """

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def aggregated_timeseries_data_query(ids, slugs, from, to, aggregation) do
    params = view_params(ids, from, to) |> Map.put(:slugs, slugs)

    sql = """
    SELECT slug, SUM(value), toUInt32(SUM(has_changed))
    FROM (
      SELECT
        arrayJoin({{slugs:Array(String)}}) AS slug,
        toFloat64(0) AS value,
        toUInt32(0) AS has_changed

      UNION ALL

      SELECT
        dictGetString('asset_metadata_dict', 'name', asset_id) AS slug,
        #{aggregation(aggregation, "combined_labeled_balance", "dt")} AS value,
        toUInt32(1) AS has_changed
      FROM #{view_call()}
      #{pairs_filter(ids)}
      GROUP BY asset_id
    )
    GROUP BY slug
    """

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp value_columns(:ohlc), do: ["open", "high", "low", "close"]
  defp value_columns(_), do: ["value"]

  # The OHLC aggregation already names its columns
  defp aggregation_columns(:ohlc), do: aggregation(:ohlc, "combined_labeled_balance", "dt")

  defp aggregation_columns(aggregation),
    do: "#{aggregation(aggregation, "combined_labeled_balance", "dt")} AS value"

  # `span` is the number of intervals in the time range. For the interval functions
  # (toStartOfMonth, etc.) it is approximate, so two more are generated and the ones
  # after `to` are dropped.
  defp timeseries_params(ids, from, to, interval) do
    {_from, _to, _interval, span} = timerange_parameters(from, to, interval)

    view_params(ids, from, to)
    |> Map.merge(%{interval: maybe_str_to_sec(interval), span: span + 2})
  end

  defp view_call() do
    """
    default.cumulative_labeled_balance(
      asset_ids = {{asset_ids:Array(UInt64)}},
      label_ids = {{label_ids:Array(UInt64)}},
      metric_id = {{metric_id:UInt64}},
      from_dt = toDateTime({{from}}),
      to_dt = toDateTime({{to}})
    )
    """
  end

  defp view_params(ids, from, to) do
    %{
      asset_ids: Enum.map(ids.pairs, &elem(&1, 0)) |> Enum.uniq(),
      label_ids: Enum.map(ids.pairs, &elem(&1, 1)) |> Enum.uniq(),
      pair_asset_ids: Enum.map(ids.pairs, &elem(&1, 0)),
      pair_label_ids: Enum.map(ids.pairs, &elem(&1, 1)),
      metric_id: ids.metric_id,
      from: dt_to_unix(:from, from),
      to: dt_to_unix(:to, to)
    }
  end

  # The view returns every asset_id x label_id combination. With one label this is
  # exactly what is requested. With one label per asset (whales) the other combinations
  # are dropped.
  defp pairs_filter(%{pairs: pairs}) do
    case pairs |> Enum.map(&elem(&1, 1)) |> Enum.uniq() do
      [_] ->
        ""

      _ ->
        """
        WHERE has(
          arrayZip({{pair_asset_ids:Array(UInt64)}}, {{pair_label_ids:Array(UInt64)}}),
          (assumeNotNull(asset_id), label_id)
        )
        """
    end
  end
end
