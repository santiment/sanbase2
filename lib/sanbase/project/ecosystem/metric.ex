defmodule Sanbase.Ecosystem.Metric do
  import Sanbase.Metric.SqlQuery.Helper,
    only: [
      to_unix_timestamp: 3,
      aggregation: 3,
      generate_comparison_string: 3,
      asset_id_filter: 2,
      additional_filters: 3,
      dt_to_unix: 2
    ]

  def aggregated_timeseries_data(ecosystems, metric, from, to, aggregation) do
    query = aggregated_timeseries_data(ecosystems, metric, from, to, aggregation)

    case Sanbase.ClickhouseRepo.query_transform(query, & &1) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  # Private functions

  defp aggregated_timeseries_data_query(ecosystems, metric, from, to, aggregation) do
    sql = """
    WITH
        ecosystem_assets AS (
            SELECT ecosystem, asset_id
            FROM ecosystem_assets_mapping
            WHERE ecosystem IN {{ecosystems}}
            ARRAY JOIN asset_ids AS asset_id
        ),
        asset_ids AS (SELECT asset_id FROM ecosystem_assets),
        asset_dev_activity AS (
            SELECT asset_id, sum(value) as dev_activity_sum_per_asset_id
            FROM intraday_metrics
            WHERE metric_id = (SELECT metric_id FROM metric_metadata WHERE name = 'dev_activity' LIMIT 1)
              AND asset_id IN asset_ids
              AND dt > {{from}} AND dt <= {{to}}
            GROUP BY asset_id
        ),
        ecosystem_dev_activity AS (
            SELECT *
            FROM ecosystem_assets
            INNER JOIN asset_dev_activity
            USING asset_id
        )
    SELECT
      ecosystem,
      groupArray(asset_id) AS asset_ids,
      sum(dev_activity_sum_per_asset_id) AS dev_activity_sum
    FROM ecosystem_dev_activity
    GROUP BY ecosystem
    """

    params = %{ecosystems: ecosystems, from: dt_to_unix(:from, from), to: dt_to_unix(:to, to)}

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def timeseries_data(ecosystems, metric, from, to, interval, aggregation) do
    sql = """


    """

    params = %{
      ecosystems: ecosystems
    }
  end
end
