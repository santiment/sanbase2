defmodule Sanbase.Metric.LatestMetric do
  @moduledoc false
  ##
  ## This is a temprorary test module that won't live long
  ##
  import Sanbase.Metric.SqlQuery.Helper, only: [asset_id_filter: 2, metric_id_filter: 2]

  alias Sanbase.Clickhouse.MetricAdapter.FileHandler

  @name_to_metric_map FileHandler.name_to_metric_map()
  @metric_to_name_map FileHandler.metric_to_name_map()
  @table_map FileHandler.table_map()

  def latest_metrics_data(metrics, %{slug: slug_or_slugs}) do
    slugs = List.wrap(slug_or_slugs)

    metric_table_groups = Enum.group_by(metrics, &Map.get(@table_map, &1))

    {:ok, intraday_result} =
      get_data("intraday_metrics", metric_table_groups["intraday_metrics"] || [], slugs)

    {:ok, daily_result} =
      get_data("daily_metrics_v2", metric_table_groups["daily_metrics_v2"] || [], slugs)

    {:ok, intraday_result ++ daily_result}
  end

  defp get_data(_table, [], _slugs), do: {:ok, []}
  defp get_data(_table, _metrics, []), do: {:ok, []}

  defp get_data(table, metrics, slugs) do
    {query, args} = get_data_query(table, metrics, slugs)

    Sanbase.ClickhouseRepo.query_transform(
      query,
      args,
      fn [slug, metric, value, dt_unix, computed_at_unix] ->
        %{
          slug: slug,
          metric: Map.get(@metric_to_name_map, metric),
          value: value,
          datetime: DateTime.from_unix!(dt_unix),
          computed_at: DateTime.from_unix!(computed_at_unix)
        }
      end
    )
  end

  defp get_data_query(table, metrics, slugs) do
    query = """
    SELECT
      name AS slug,
      metric_id,
      argMax(value, dt) AS value,
      toUnixTimestamp(max(toDateTime(dt))) AS max_dt,
      toUnixTimestamp(argMax(computed_at, dt)) AS computed_at
    FROM(
      SELECT
        asset_id,
        metric_id,
        dt,
        computed_at,
        value
      FROM #{table}
      PREWHERE
        dt >= now() - INTERVAL 7 DAY AND dt <= now() AND
        #{metric_id_filter(metrics, argument_position: 1)} AND
        #{asset_id_filter(slugs, argument_position: 2)}
    )
    INNER JOIN (
      SELECT asset_id, name
      FROM asset_metadata FINAL
    ) USING (asset_id)
    GROUP BY metric_id, asset_id, name
    """

    query = """
    SELECT slug, name AS metric, value, max_dt, computed_at
    FROM (#{query})
    INNER JOIN (
      SELECT metric_id, name
      FROM metric_metadata FINAL
    ) USING (metric_id)
    """

    args = [Enum.map(metrics, &Map.get(@name_to_metric_map, &1)), slugs]
    {query, args}
  end
end
