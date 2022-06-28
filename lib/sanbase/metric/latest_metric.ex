defmodule Sanbase.Metric.LatestMetric do
  @moduledoc false
  ##
  ## This is a temprorary test module that won't live long
  ##
  import Sanbase.Metric.SqlQuery.Helper,
    only: [asset_id_filter: 2, metric_id_filter: 2, aggregation: 3]

  alias Sanbase.Clickhouse.MetricAdapter.FileHandler

  @name_to_metric_map FileHandler.name_to_metric_map()
  @metric_to_names_map FileHandler.metric_to_names_map()
  @table_map FileHandler.table_map()
  @asset_prices_table Sanbase.Price.table()

  def latest_metrics_data(metrics, %{slug: slug_or_slugs}) do
    slugs = List.wrap(slug_or_slugs)

    metric_table_groups = metrics_table_groups(metrics)

    {:ok, intraday_result} =
      get_data("intraday_metrics", metric_table_groups["intraday_metrics"] || [], slugs)

    {:ok, daily_result} =
      get_data("daily_metrics_v2", metric_table_groups["daily_metrics_v2"] || [], slugs)

    {:ok, price_result} =
      get_data(@asset_prices_table, metric_table_groups[@asset_prices_table] || [], slugs)

    # For now support only price_usd and price_btc and take them from the asset price pairs table
    {:ok, price_pairs_result} =
      get_data(@asset_prices_table, metric_table_groups["asset_price_pairs_only"] || [], slugs,
        source: "cryptocompare",
        metric_name_suffix: "|cryptocompare"
      )

    result = Enum.concat([intraday_result, daily_result, price_result, price_pairs_result])
    {:ok, result}
  end

  defp metrics_table_groups(metrics) do
    Enum.reduce(metrics, %{}, fn metric, acc ->
      {metric, table} = get_metric_table_pair(metric)
      Map.update(acc, table, [metric], &[metric | &1])
    end)
  end

  defp get_metric_table_pair(metric) do
    case String.split(metric, "|") do
      [metric] when metric in ["price_usd", "price_btc", "volume_usd", "marketcap_usd"] ->
        {metric, @asset_prices_table}

      [metric] ->
        {metric, Map.get(@table_map, metric)}

      [metric, "cryptocompare"] ->
        {metric, "asset_price_pairs_only"}
    end
  end

  def get_data(table, metrics, slugs, opts \\ [])
  def get_data(_table, [], _slugs, _opts), do: {:ok, []}
  def get_data(_table, _metrics, [], _opts), do: {:ok, []}

  def get_data(table, metrics, slugs, opts) do
    {query, args} = get_data_query(table, metrics, slugs, opts)

    Sanbase.ClickhouseRepo.query_transform(
      query,
      args,
      fn [slug, metric, value, dt_unix, computed_at_unix] ->
        %{
          slug: slug,
          metric: get_metric_name(table, metric),
          value: value,
          datetime: DateTime.from_unix!(dt_unix),
          computed_at: DateTime.from_unix!(computed_at_unix)
        }
      end
    )
  end

  defp get_metric_name(table, metric) when table in ["intraday_metrics", "daily_metrics_v2"] do
    name = Map.get(@metric_to_names_map, metric, []) |> List.first()
    name || metric
  end

  defp get_metric_name(_table, metric), do: metric

  defp get_data_query(table, metrics, slugs, _opts)
       when table in ["intraday_metrics", "daily_metrics_v2"] do
    query = """
    SELECT
      dictGetString('asset_metadata_dict', 'name', asset_id) AS slug,
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
        dt >= now() - INTERVAL 7 DAY AND dt <= now() AND dt < computed_at AND
        #{metric_id_filter(metrics, argument_position: 1)} AND
        #{asset_id_filter(%{slug: slugs}, argument_position: 2)}
    )
    INNER JOIN (
      SELECT asset_id, name
      FROM asset_metadata FINAL
    ) USING (asset_id)
    GROUP BY asset_id,metric_id, name
    """

    args = [Enum.map(metrics, &Map.get(@name_to_metric_map, &1)), slugs]
    {query, args}
  end

  defp get_data_query(@asset_prices_table, metrics, slugs, opts) do
    source = Keyword.get(opts, :source, "coinmarketcap")
    metric_name_suffix = Keyword.get(opts, :metric_name_suffix, "")

    metrics_aggregated_selector_str =
      Enum.map(metrics, fn m -> "#{aggregation(:last, "#{m}", "dt")} AS #{m}" end)
      |> Enum.join("\n,")

    query = """
    SELECT
      cast(slug, 'String') AS slugString,
      toUnixTimestamp(max(dt)) AS dt2,
      #{metrics_aggregated_selector_str}
    FROM asset_prices_v3
      PREWHERE slug IN (?1) AND
      dt >= now() - INTERVAL 7 DAY AND dt <= now() AND
      source = cast(?2, 'LowCardinality(String)')
    GROUP BY slug
    """

    metrics_pairs_str = Enum.map(metrics, fn m -> "(#{m}, '#{m}')" end) |> Enum.join(",")

    query = """
    SELECT slugString, concat(tuple.2, ?3) AS metric, tuple.1 AS value, dt2 AS dt, dt2 AS computed_at FROM
    ( SELECT slugString, arrayJoin([#{metrics_pairs_str}]) AS tuple, dt2 FROM (#{query}) )
    """

    args = [slugs, source, metric_name_suffix]

    {query, args}
  end
end
