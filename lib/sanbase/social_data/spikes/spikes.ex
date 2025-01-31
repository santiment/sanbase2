defmodule Sanbase.SocialData.Spikes do
  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2]

  import Sanbase.Metric.SqlQuery.Helper,
    only: [asset_id_filter: 2, metric_id_filter: 2, to_unix_timestamp: 3]

  def get_metric_spike_explanations(metric, selector, from, to) do
    query =
      get_metric_spikes_explanations_query(metric, selector, from, to)

    Sanbase.ClickhouseRepo.query_transform(query, fn [from, to, summary] ->
      %{
        spike_start_datetime: DateTime.from_unix!(from),
        spike_end_datetime: DateTime.from_unix!(to),
        explanation: summary
      }
    end)
  end

  def get_metric_spike_explanations_count(metric, selector, from, to, interval) do
    query =
      get_metric_spikes_explanations_count_query(metric, selector, from, to, interval)

    Sanbase.ClickhouseRepo.query_transform(query, fn [dt, count] ->
      %{
        datetime: DateTime.from_unix!(dt),
        count: count
      }
    end)
  end

  def available_assets() do
    query_struct = available_assets_query()
    Sanbase.ClickhouseRepo.query_transform(query_struct, fn [slug] -> slug end)
  end

  def available_assets(metric) do
    query_struct = available_assets_query(metric)
    Sanbase.ClickhouseRepo.query_transform(query_struct, fn [slug] -> slug end)
  end

  def available_metrics() do
    names_map = Sanbase.Clickhouse.MetricAdapter.Registry.metric_to_names_map()
    query_struct = available_metrics_query()

    Sanbase.ClickhouseRepo.query_transform(query_struct, fn [metric] ->
      Map.get(names_map, metric, []) |> List.first()
    end)
    |> maybe_apply_function(fn list -> Enum.reject(list, &is_nil/1) end)
  end

  def available_metrics(%{slug: _} = selector) do
    names_map = Sanbase.Clickhouse.MetricAdapter.Registry.metric_to_names_map()
    query_struct = available_metrics_query(selector)

    Sanbase.ClickhouseRepo.query_transform(query_struct, fn [metric] ->
      Map.get(names_map, metric, []) |> List.first()
    end)
    |> maybe_apply_function(fn list -> Enum.reject(list, &is_nil/1) end)
  end

  # Private functions

  defp get_metric_spikes_explanations_query(metric, %{slug: slug_or_slugs} = selector, from, to) do
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

  defp get_metric_spikes_explanations_count_query(
         metric,
         %{slug: slug} = selector,
         from,
         to,
         interval
       ) do
    sql = """
    SELECT
      #{to_unix_timestamp(interval, "from_dt", argument_name: "interval")} AS t,
      count(*) AS summaries_count
    FROM spikes
    WHERE
      #{asset_id_filter(selector, argument_name: "selector")} AND
      #{metric_id_filter(metric, metric_id_column: "calculated_on_metric_id", argument_name: "metric")} AND
      to_dt >= toDateTime({{from}}) AND
      from_dt < toDateTime({{to}})
    GROUP BY t
    ORDER BY t ASC
    """

    {:ok, metadata} = Sanbase.Metric.metadata(metric)

    params = %{
      selector: slug,
      metric: metadata.internal_metric,
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to),
      interval: Sanbase.DateTimeUtils.str_to_sec(interval)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp available_assets_query() do
    sql = """
    SELECT DISTINCT get_asset_name(asset_id)
    FROM spikes
    """

    Sanbase.Clickhouse.Query.new(sql, %{})
  end

  defp available_assets_query(metric) do
    sql = """
    SELECT DISTINCT get_asset_name(asset_id)
    FROM spikes
    WHERE
      #{metric_id_filter(metric, metric_id_column: "calculated_on_metric_id", argument_name: "metric")}
    """

    {:ok, metadata} = Sanbase.Metric.metadata(metric)
    Sanbase.Clickhouse.Query.new(sql, %{metric: metadata.internal_metric})
  end

  defp available_metrics_query() do
    sql = """
    SELECT DISTINCT get_metric_name(calculated_on_metric_id)
    FROM spikes
    """

    Sanbase.Clickhouse.Query.new(sql, %{})
  end

  defp available_metrics_query(%{slug: slug} = selector) do
    sql = """
    SELECT DISTINCT get_metric_name(calculated_on_metric_id)
    FROM spikes
    WHERE
    #{asset_id_filter(selector, argument_name: "selector")}
    """

    params = %{selector: slug}

    Sanbase.Clickhouse.Query.new(sql, params)
  end
end
