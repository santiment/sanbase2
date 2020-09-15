defmodule Sanbase.Clickhouse.Metric do
  @table "daily_metrics_v2"

  @moduledoc ~s"""
  Provide access to the v2 metrics in Clickhouse

  The metrics are stored in the '#{@table}' clickhouse table where each metric
  is defined by a `metric_id` and every project is defined by an `asset_id`.
  """
  @behaviour Sanbase.Metric.Behaviour

  import Sanbase.Clickhouse.MetadataHelper
  import Sanbase.Clickhouse.Metric.SqlQuery
  import Sanbase.Utils.Transform, only: [maybe_unwrap_ok_value: 1]

  alias __MODULE__.{HistogramMetric, FileHandler}

  alias Sanbase.ClickhouseRepo

  @plain_aggregations FileHandler.aggregations()
  @aggregations [nil] ++ @plain_aggregations
  @timeseries_metrics_name_list FileHandler.metrics_with_data_type(:timeseries)
  @histogram_metrics_name_list FileHandler.metrics_with_data_type(:histogram)
  @table_metrics_name_list FileHandler.metrics_with_data_type(:table)
  @access_map FileHandler.access_map()
  @min_plan_map FileHandler.min_plan_map()
  @min_interval_map FileHandler.min_interval_map()
  @free_metrics FileHandler.metrics_with_access(:free)
  @restricted_metrics FileHandler.metrics_with_access(:restricted)
  @aggregation_map FileHandler.aggregation_map()
  @human_readable_name_map FileHandler.human_readable_name_map()
  @metrics_data_type_map FileHandler.metrics_data_type_map()
  @metrics_name_list (@histogram_metrics_name_list ++
                        @timeseries_metrics_name_list ++ @table_metrics_name_list)
                     |> Enum.uniq()
  @metrics_mapset @metrics_name_list |> MapSet.new()
  @incomplete_data_map FileHandler.incomplete_data_map()
  @selectors_map FileHandler.selectors_map()
  @tables_list FileHandler.table_map() |> Map.values() |> List.flatten() |> Enum.uniq()

  @default_complexity_weight 0.3

  @type slug :: String.t()
  @type metric :: String.t()
  @type interval :: String.t()

  @impl Sanbase.Metric.Behaviour
  def free_metrics(), do: @free_metrics

  @impl Sanbase.Metric.Behaviour
  def restricted_metrics(), do: @restricted_metrics

  @impl Sanbase.Metric.Behaviour
  def access_map(), do: @access_map

  @impl Sanbase.Metric.Behaviour
  def min_plan_map(), do: @min_plan_map

  @impl Sanbase.Metric.Behaviour
  def has_incomplete_data?(metric), do: Map.get(@incomplete_data_map, metric)

  @impl Sanbase.Metric.Behaviour
  def complexity_weight(_), do: @default_complexity_weight

  @doc ~s"""
  Get a given metric for a slug and time range. The metric's aggregation
  function can be changed by the last optional parameter. The available
  aggregations are #{inspect(@plain_aggregations)}
  """
  @impl Sanbase.Metric.Behaviour

  def timeseries_data(_metric, %{slug: []}, _from, _to, _interval, _opts), do: {:ok, []}

  def timeseries_data(metric, %{slug: slug}, from, to, interval, opts) do
    aggregation = Keyword.get(opts, :aggregation, nil) || Map.get(@aggregation_map, metric)
    filters = Keyword.get(opts, :additional_filters, [])

    {query, args} = timeseries_data_query(metric, slug, from, to, interval, aggregation, filters)

    ClickhouseRepo.query_transform(query, args, fn [unix, value] ->
      %{
        datetime: DateTime.from_unix!(unix),
        value: value
      }
    end)
  end

  @impl Sanbase.Metric.Behaviour
  defdelegate histogram_data(metric, slug, from, to, interval, limit), to: HistogramMetric

  @impl Sanbase.Metric.Behaviour

  def table_data(_metric, nil, _from, _to, _opts), do: {:ok, %{}}

  def table_data(_metric, [], _from, _to, _opts), do: {:ok, %{}}

  def table_data(metric, selector, from, to, limit) do
    aggregation = Keyword.get(opts, :aggregation, nil) || Map.get(@aggregation_map, metric)

    {query, args} = table_data_query(metric, selector, from, to, interval, limit)

    ClickhouseRepo.query_transform(query, args, fn %{columns: columns, rows: rows, values: values} ->
      %{
        columns: columns,
        rows: rows,
        values: values
      }
    end)
  end

  @impl Sanbase.Metric.Behaviour
  def aggregated_timeseries_data(metric, selector, from, to, opts)

  def aggregated_timeseries_data(_metric, nil, _from, _to, _opts), do: {:ok, %{}}
  def aggregated_timeseries_data(_metric, [], _from, _to, _opts), do: {:ok, %{}}

  def aggregated_timeseries_data(metric, %{slug: slug_or_slugs}, from, to, opts)
      when is_binary(slug_or_slugs) or is_list(slug_or_slugs) do
    aggregation = Keyword.get(opts, :aggregation, nil) || Map.get(@aggregation_map, metric)
    filters = Keyword.get(opts, :additional_filters, [])
    slugs = List.wrap(slug_or_slugs)
    get_aggregated_timeseries_data(metric, slugs, from, to, aggregation, filters)
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_by_filter(metric, from, to, operator, threshold, opts) do
    aggregation = Keyword.get(opts, :aggregation, nil) || Map.get(@aggregation_map, metric)
    filters = Keyword.get(opts, :additional_filters, [])

    {query, args} =
      slugs_by_filter_query(metric, from, to, operator, threshold, aggregation, filters)

    ClickhouseRepo.query_transform(query, args, fn [slug, _value] -> slug end)
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_order(metric, from, to, direction, opts) do
    aggregation = Keyword.get(opts, :aggregation, nil) || Map.get(@aggregation_map, metric)
    filters = Keyword.get(opts, :additional_filters, [])

    {query, args} = slugs_order_query(metric, from, to, direction, aggregation, filters)
    ClickhouseRepo.query_transform(query, args, fn [slug, _value] -> slug end)
  end

  @impl Sanbase.Metric.Behaviour
  def metadata(metric) do
    min_interval = min_interval(metric)
    default_aggregation = Map.get(@aggregation_map, metric)

    {:ok,
     %{
       metric: metric,
       min_interval: min_interval,
       default_aggregation: default_aggregation,
       available_aggregations: @plain_aggregations,
       available_selectors: Map.get(@selectors_map, metric),
       data_type: Map.get(@metrics_data_type_map, metric),
       complexity_weight: @default_complexity_weight
     }}
  end

  @impl Sanbase.Metric.Behaviour
  def human_readable_name(metric) do
    {:ok, Map.get(@human_readable_name_map, metric)}
  end

  @doc ~s"""
  Return a list of available metrics.
  """

  @impl Sanbase.Metric.Behaviour
  def available_histogram_metrics(), do: @histogram_metrics_name_list

  @impl Sanbase.Metric.Behaviour
  def available_timeseries_metrics(), do: @timeseries_metrics_name_list

  @impl Sanbase.Metric.Behaviour
  def available_table_metrics(), do: @table_metrics_name_list

  @impl Sanbase.Metric.Behaviour
  def available_metrics(), do: @metrics_name_list

  @impl Sanbase.Metric.Behaviour
  def available_metrics(%{slug: slug}) when is_binary(slug) do
    Enum.reduce_while(@tables_list, [], fn table, acc ->
      case available_metrics_in_table(table, slug) do
        {:ok, metrics} ->
          {:cont, metrics ++ acc}

        _ ->
          {:halt, {:error, "Error fetching available metrics for #{slug}"}}
      end
    end)
    |> case do
      {:error, error} -> {:error, error}
      metrics when is_list(metrics) -> {:ok, metrics}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def available_slugs(), do: get_available_slugs()

  @impl Sanbase.Metric.Behaviour
  def available_slugs(metric), do: get_available_slugs(metric)

  @impl Sanbase.Metric.Behaviour
  def available_aggregations(), do: @aggregations

  @impl Sanbase.Metric.Behaviour
  def first_datetime(metric, selector)
      when metric in ["price_histogram", "spent_coins_cost", "all_spent_coins_cost"],
      do: HistogramMetric.first_datetime(metric, selector)

  def first_datetime(metric, %{slug: slug}) do
    {query, args} = first_datetime_query(metric, slug)

    ClickhouseRepo.query_transform(query, args, fn [datetime] ->
      DateTime.from_unix!(datetime)
    end)
    |> maybe_unwrap_ok_value()
  end

  @impl Sanbase.Metric.Behaviour
  def last_datetime_computed_at(metric, selector)
      when metric in ["price_histogram", "spent_coins_cost", "all_spent_coins_cost"],
      do: HistogramMetric.last_datetime_computed_at(metric, selector)

  def last_datetime_computed_at(metric, %{slug: slug}) do
    {query, args} = last_datetime_computed_at_query(metric, slug)

    ClickhouseRepo.query_transform(query, args, fn [datetime] ->
      DateTime.from_unix!(datetime)
    end)
    |> maybe_unwrap_ok_value()
  end

  # Private functions

  defp min_interval(metric), do: Map.get(@min_interval_map, metric)

  defp get_available_slugs() do
    # NOTE: Fetch the metrics from the daily_metrics_v2 only for performance reasons
    # currently searching in the intraday and distributions tables does not
    # add slugs that are not present in the daily metrics
    {query, args} = available_slugs_in_table_query("daily_metrics_v2")

    ClickhouseRepo.query_transform(query, args, fn [slug] -> slug end)
  end

  defp get_available_slugs(metric) do
    {query, args} = available_slugs_for_metric_query(metric)

    ClickhouseRepo.query_transform(query, args, fn [slug] -> slug end)
  end

  defp get_aggregated_timeseries_data(metric, slugs, from, to, aggregation, filters)
       when is_list(slugs) and length(slugs) > 50 do
    result =
      Enum.chunk_every(slugs, 50)
      |> Sanbase.Parallel.map(
        &get_aggregated_timeseries_data(metric, &1, from, to, aggregation, filters),
        timeout: 25_000,
        max_concurrency: 8,
        ordered: false,
        on_timeout: :kill_task
      )
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(&elem(&1, 1))
      |> Enum.reduce(%{}, &Map.merge(&1, &2))

    {:ok, result}
  end

  defp get_aggregated_timeseries_data(metric, slugs, from, to, aggregation, filters)
       when is_list(slugs) do
    {:ok, asset_map} = slug_to_asset_id_map()

    case Map.take(asset_map, slugs) |> Map.values() do
      [] ->
        {:ok, %{}}

      asset_ids ->
        {:ok, asset_id_map} = asset_id_to_slug_map()

        {query, args} =
          aggregated_timeseries_data_query(metric, asset_ids, from, to, aggregation, filters)

        ClickhouseRepo.query_reduce(query, args, %{}, fn [asset_id, value], acc ->
          slug = Map.get(asset_id_map, asset_id)
          Map.put(acc, slug, value)
        end)
    end
  end

  def available_metrics_in_table(table, slug) do
    {query, args} = available_metrics_in_table_query(table, slug)

    {:ok, metric_map} = metric_id_to_metric_name_map()

    ClickhouseRepo.query_reduce(query, args, [], fn [metric_id], acc ->
      metrics = Map.get(metric_map, metric_id |> Sanbase.Math.to_integer())

      case metrics != nil and metrics != [] do
        true ->
          metrics = Enum.filter(metrics, &(&1 in @metrics_mapset))
          metrics ++ acc

        false ->
          acc
      end
    end)
  end
end
