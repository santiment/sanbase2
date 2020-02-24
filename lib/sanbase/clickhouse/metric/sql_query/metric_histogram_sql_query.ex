defmodule Sanbase.Clickhouse.Metric.HistogramSqlQuery do
  alias Sanbase.Clickhouse.Metric.FileHandler

  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]
  @table_map FileHandler.table_map()
  @name_to_metric_map FileHandler.name_to_metric_map()

  def histogram_data_query("price_histogram", slug, from, to, interval, _limit) do
    query = """
    SELECT round(price, 2) AS price, sum(tokens_amount) AS tokens_amount
    FROM (
      SELECT *
      FROM (
        SELECT
            toUnixTimestamp(intDiv(toUInt32(toDateTime(value)), ?4) * ?4) AS t,
            -sum(measure) AS tokens_amount
        FROM distribution_deltas_5min FINAL
        PREWHERE
          asset_id = ( SELECT argMax(asset_id, computed_at) FROM asset_metadata PREWHERE name = ?1 ) AND
          dt >= toDateTime(?2) AND
          dt < toDateTime(?3) AND
          dt != value
        GROUP BY t
        ORDER BY t ASC
      )
      ALL LEFT JOIN
      (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?4) * ?4) AS t,
          avg(value) AS price
        FROM intraday_metrics FINAL
        PREWHERE
          asset_id = (SELECT asset_id FROM asset_metadata FINAL PREWHERE name = ?1) AND
          metric_id = (SELECT metric_id FROM metric_metadata FINAL PREWHERE name = 'price_usd')
        GROUP BY t
      ) USING (t)
    )
    GROUP BY price
    ORDER BY price ASC
    """

    args = [
      slug,
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix(),
      interval |> str_to_sec()
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
      metric_id = ( SELECT argMax(metric_id, computed_at) FROM metric_metadata PREWHERE name = ?1 ) AND
      asset_id = ( SELECT argMax(asset_id, computed_at) FROM asset_metadata PREWHERE name = ?2 ) AND
      dt != value AND
      dt >= toDateTime(?3) AND
      dt < toDateTime(?4)
    GROUP BY t
    ORDER BY t DESC
    LIMIT ?6
    """

    args = [
      Map.get(@name_to_metric_map, metric),
      slug,
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix(),
      interval |> str_to_sec(),
      limit
    ]

    {query, args}
  end
end
