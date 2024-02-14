defmodule Sanbase.Ecosystem.Metric do
  import Sanbase.DateTimeUtils, only: [maybe_str_to_sec: 1]

  import Sanbase.Metric.SqlQuery.Helper,
    only: [
      to_unix_timestamp: 3,
      aggregation: 3,
      dt_to_unix: 2
    ]

  alias Sanbase.Clickhouse.MetricAdapter.FileHandler
  @name_to_metric_map FileHandler.name_to_metric_map()
  @aggregation_map FileHandler.aggregation_map()

  def aggregated_timeseries_data(ecosystems, metric, from, to, opts) do
    aggregation = Keyword.get(opts, :aggregation, nil) || Map.get(@aggregation_map, metric)
    query = aggregated_timeseries_data_query(ecosystems, metric, from, to, aggregation)

    case Sanbase.ClickhouseRepo.query_transform(query, & &1) do
      {:ok, data} ->
        result =
          Enum.map(data, fn [ecosystem, value] -> %{ecosystem: ecosystem, value: value} end)

        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
  end

  def timeseries_data(ecosystems, metric, from, to, interval, opts) do
    aggregation = Keyword.get(opts, :aggregation, nil) || Map.get(@aggregation_map, metric)
    query = timeseries_data_query(ecosystems, metric, from, to, interval, aggregation)

    case Sanbase.ClickhouseRepo.query_transform(query, & &1) do
      {:ok, data} ->
        result =
          Enum.map(data, fn [ecosystem, dt, value] ->
            %{ecosystem: ecosystem, datetime: DateTime.from_unix!(dt), value: value}
          end)

        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
  end

  # Private functions

  defp aggregated_timeseries_data_query(ecosystems, metric, from, to, aggregation) do
    params = %{
      ecosystems: ecosystems,
      metric: Map.get(@name_to_metric_map, metric),
      from: dt_to_unix(:from, from),
      to: dt_to_unix(:to, to)
    }

    sql = """
    SELECT
      ecosystem,
      #{aggregation(aggregation, "value", "dt")} AS value
    FROM(
      SELECT dt, ecosystem, argMax(value, computed_at) AS value
      FROM (
        SELECT dt, ecosystem, metric_id, value, computed_at
        FROM ecosystem_aggregated_metrics
        WHERE
          ecosystem IN ({{ecosystems}}) AND
          metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = {{metric}} LIMIT 1 ) AND
          dt >= toDateTime({{from}}) AND dt < toDateTime({{to}})
        )
        GROUP BY ecosystem, dt
    )
    GROUP BY ecosystem
    """

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp timeseries_data_query(ecosystems, metric, from, to, interval, aggregation) do
    params = %{
      interval: maybe_str_to_sec(interval),
      metric: Map.get(@name_to_metric_map, metric),
      from: dt_to_unix(:from, from),
      to: dt_to_unix(:to, to),
      ecosystems: ecosystems
    }

    sql = """
    SELECT
      ecosystem,
      #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS t,
      #{aggregation(aggregation, "value", "dt")} AS value
    FROM(
      SELECT
        ecosystem,
        dt,
        argMax(value, computed_at) AS value
      FROM ecosystem_aggregated_metrics
      PREWHERE
        ecosystem IN ({{ecosystems}}) AND
        metric_id = ( SELECT metric_id FROM metric_metadata FINAL PREWHERE name = {{metric}} LIMIT 1 ) AND
        dt >= toDateTime({{from}}) AND dt < toDateTime({{to}})
      GROUP BY ecosystem, dt
    )
    GROUP BY ecosystem, t
    ORDER BY t
    """

    Sanbase.Clickhouse.Query.new(sql, params)
  end
end
