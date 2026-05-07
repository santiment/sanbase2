defmodule Sanbase.Hyperliquid.Bbo.BboSqlQuery do
  @table "hyperliquid_bbo_prices"

  import Sanbase.Utils.DateTime, only: [maybe_str_to_sec: 1]

  import Sanbase.Metric.SqlQuery.Helper,
    only: [to_unix_timestamp: 3, dt_to_unix: 2]

  def timeseries_data_query(slug, from, to, interval) do
    sql = """
    SELECT
      time,
      tupleElement(r, 1) AS bid_price,
      tupleElement(r, 2) AS bid_volume,
      tupleElement(r, 3) AS ask_price,
      tupleElement(r, 4) AS ask_volume
    FROM (
      SELECT
        #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS time,
        argMax((bid_price, bid_volume, ask_price, ask_volume), dt) AS r
      FROM #{@table}
      WHERE
        slug = cast({{slug}}, 'LowCardinality(String)') AND
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}})
      GROUP BY time
    )
    ORDER BY time ASC
    """

    params = %{
      interval: maybe_str_to_sec(interval),
      slug: slug,
      from: dt_to_unix(:from, from),
      to: dt_to_unix(:to, to)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end
end
