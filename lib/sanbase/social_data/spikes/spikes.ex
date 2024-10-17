defmodule Sanbase.SocialData.Spikes do
  import Sanbase.Metric.SqlQuery.Helper,
    only: [asset_id_filter: 2, metric_id_filter: 2]

  def get_metric_spike_explanations(metric, selector, from, to) do
    query =
      get_metric_spikes_explanation_query(metric, selector, from, to)

    Sanbase.ClickhouseRepo.query_transform(query, fn [from, to, summary] ->
      %{
        spike_start_datetime: DateTime.from_unix!(from),
        spike_end_datetime: DateTime.from_unix!(to),
        explanation: summary
      }
    end)
  end

  defp get_metric_spikes_explanation_query(metric, %{slug: slug_or_slugs} = selector, from, to) do
    sql = """
    SELECT
      toUnixTimestamp(from_dt),
      toUnixTimestamp(to_dt),
      summary
    FROM spikes
    WHERE
      #{asset_id_filter(selector, argument_name: "selector")} AND
      #{metric_id_filter(metric, metric_id_column: "calculated_on_metric_id", argument_name: "metric")} AND
      to_dt >= toDateTime({{from}}) AND
      from_dt < toDateTime({{to}})
    ORDER BY from_dt ASC
    """

    {:ok, metadata} = Sanbase.Metric.metadata(metric)

    params = %{
      selector: slug_or_slugs,
      metric: metadata.internal_metric,
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end
end
