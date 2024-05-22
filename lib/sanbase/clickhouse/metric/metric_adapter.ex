defmodule Sanbase.Clickhouse.MetricAdapter do
  @moduledoc ~s"""
  Provide access to the v2 metrics in Clickhouse

  The metrics are stored in clickhouse tables where each metric
  is defined by a `metric_id` and every project is defined by an `asset_id`.
  """
  @behaviour Sanbase.Metric.Behaviour

  import Sanbase.Clickhouse.MetricAdapter.SqlQuery
  import Sanbase.Metric.Transform, only: [exec_timeseries_data_query: 1]

  import Sanbase.Utils.Transform, only: [maybe_unwrap_ok_value: 1, maybe_apply_function: 2]

  alias __MODULE__.{HistogramMetric, FileHandler, TableMetric}

  alias Sanbase.ClickhouseRepo

  @plain_aggregations FileHandler.aggregations()
  @aggregations [nil] ++ @plain_aggregations
  @timeseries_metrics_name_list FileHandler.metrics_with_data_type(:timeseries)
  @histogram_metrics_name_list FileHandler.metrics_with_data_type(:histogram)
  @table_structured_metrics_name_list FileHandler.metrics_with_data_type(:table)
  @access_map FileHandler.access_map()
  @min_plan_map FileHandler.min_plan_map()
  @min_interval_map FileHandler.min_interval_map()
  @free_metrics FileHandler.metrics_with_access(:free)
  @restricted_metrics FileHandler.metrics_with_access(:restricted)
  @aggregation_map FileHandler.aggregation_map()
  @docs_links_map FileHandler.docs_links_map()
  @human_readable_name_map FileHandler.human_readable_name_map()
  @metrics_data_type_map FileHandler.metrics_data_type_map()
  @metrics_name_list (@histogram_metrics_name_list ++
                        @timeseries_metrics_name_list ++ @table_structured_metrics_name_list)
                     |> Enum.uniq()
  @metrics_mapset @metrics_name_list |> MapSet.new()
  @incomplete_data_map FileHandler.incomplete_data_map()
  @selectors_map FileHandler.selectors_map()
  @required_selectors_map FileHandler.required_selectors_map()
  @metric_to_names_map FileHandler.metric_to_names_map()
  @name_to_metric_map FileHandler.name_to_metric_map()
  @deprecated_metrics_map FileHandler.deprecated_metrics_map()
  @soft_deprecated_metrics_map FileHandler.soft_deprecated_metrics_map()
  @timebound_flag_map FileHandler.timebound_flag_map()

  @fixed_labels_parameters_metrics_mapset FileHandler.fixed_labels_parameters_metrics_mapset()
  @fixed_labels_parameters_metrics Enum.to_list(@fixed_labels_parameters_metrics_mapset)
  @fixed_parameteres_map FileHandler.fixed_parameters_map()

  @default_complexity_weight 0.3

  @incomplete_metrics Enum.filter(@incomplete_data_map, &(elem(&1, 1) == true))
                      |> Enum.map(&elem(&1, 0))

  @type slug :: String.t()
  @type metric :: String.t()
  @type interval :: String.t()

  defguard is_supported_selector(s)
           when is_map(s) and
                  (is_map_key(s, :slug) or is_map_key(s, :address) or
                     is_map_key(s, :contract_address))

  @impl Sanbase.Metric.Behaviour
  def incomplete_metrics(), do: @incomplete_metrics

  @impl Sanbase.Metric.Behaviour
  def free_metrics(), do: @free_metrics

  @impl Sanbase.Metric.Behaviour
  def restricted_metrics(), do: @restricted_metrics

  @impl Sanbase.Metric.Behaviour
  def fixed_labels_parameters_metrics(), do: @fixed_labels_parameters_metrics

  @impl Sanbase.Metric.Behaviour
  def deprecated_metrics_map(), do: @deprecated_metrics_map

  @impl Sanbase.Metric.Behaviour
  def soft_deprecated_metrics_map(), do: @soft_deprecated_metrics_map

  @impl Sanbase.Metric.Behaviour
  def access_map(), do: @access_map

  @impl Sanbase.Metric.Behaviour
  def min_plan_map(), do: @min_plan_map

  @impl Sanbase.Metric.Behaviour
  def has_incomplete_data?(metric), do: Map.get(@incomplete_data_map, metric)

  @impl Sanbase.Metric.Behaviour
  def complexity_weight(_), do: @default_complexity_weight

  @impl Sanbase.Metric.Behaviour
  def broken_data(_metric, _selector, _from, _to), do: {:ok, []}

  @doc ~s"""
  Get a given metric for a slug and time range. The metric's aggregation
  function can be changed by the last optional parameter. The available
  aggregations are #{inspect(@plain_aggregations)}
  """
  @impl Sanbase.Metric.Behaviour

  def timeseries_data(_metric, %{slug: []}, _from, _to, _interval, _opts), do: {:ok, []}

  def timeseries_data(metric, selector, from, to, interval, opts)
      when is_supported_selector(selector) do
    aggregation = Keyword.get(opts, :aggregation, nil) || Map.get(@aggregation_map, metric)
    opts = resolve_fixed_parameters(opts, metric)
    filters = get_filters(metric, opts)

    [
      metric,
      selector,
      filters,
      opts
    ]
    |> dbg()

    timeseries_data_query(metric, selector, from, to, interval, aggregation, filters, opts)
    |> exec_timeseries_data_query()
  end

  @impl Sanbase.Metric.Behaviour
  def timeseries_data_per_slug(metric, %{slug: slug}, from, to, interval, opts) do
    aggregation = Keyword.get(opts, :aggregation, nil) || Map.get(@aggregation_map, metric)
    filters = get_filters(metric, opts)

    timeseries_data_per_slug_query(metric, slug, from, to, interval, aggregation, filters)
    |> ClickhouseRepo.query_reduce(
      %{},
      fn [timestamp, slug, value], acc ->
        datetime = DateTime.from_unix!(timestamp)
        elem = %{slug: slug, value: value}
        Map.update(acc, datetime, [elem], &[elem | &1])
      end
    )
    |> maybe_apply_function(fn list ->
      list
      |> Enum.map(fn {datetime, data} -> %{datetime: datetime, data: data} end)
    end)
  end

  @impl Sanbase.Metric.Behaviour
  defdelegate histogram_data(metric, slug, from, to, interval, limit), to: HistogramMetric

  @impl Sanbase.Metric.Behaviour
  defdelegate table_data(metric, slug_or_slugs, from, to, opts), to: TableMetric

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

    slugs_by_filter_query(metric, from, to, operator, threshold, aggregation, filters)
    |> ClickhouseRepo.query_transform(fn [slug, _value] -> slug end)
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_order(metric, from, to, direction, opts) do
    aggregation = Keyword.get(opts, :aggregation, nil) || Map.get(@aggregation_map, metric)
    filters = Keyword.get(opts, :additional_filters, [])

    slugs_order_query(metric, from, to, direction, aggregation, filters)
    |> ClickhouseRepo.query_transform(fn [slug, _value] -> slug end)
  end

  @impl Sanbase.Metric.Behaviour
  def required_selectors(), do: FileHandler.required_selectors_map()

  @impl Sanbase.Metric.Behaviour
  def metadata(metric) do
    min_interval = min_interval(metric)
    default_aggregation = Map.get(@aggregation_map, metric)

    {:ok,
     %{
       metric: metric,
       internal_metric: Map.get(@name_to_metric_map, metric, metric),
       has_incomplete_data: has_incomplete_data?(metric),
       min_interval: min_interval,
       default_aggregation: default_aggregation,
       available_aggregations: @plain_aggregations,
       available_selectors: Map.get(@selectors_map, metric),
       required_selectors: Map.get(@required_selectors_map, metric, []),
       data_type: Map.get(@metrics_data_type_map, metric),
       is_timebound: Map.get(@timebound_flag_map, metric),
       complexity_weight: @default_complexity_weight,
       docs: Map.get(@docs_links_map, metric)
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
  def available_table_metrics(), do: @table_structured_metrics_name_list

  @impl Sanbase.Metric.Behaviour
  def available_metrics(), do: @metrics_name_list

  @impl Sanbase.Metric.Behaviour
  def available_metrics(selector) do
    available_metrics_for_selector_query(selector)
    |> ClickhouseRepo.query_transform(fn [metric] ->
      Map.get(@metric_to_names_map, metric)
    end)
    |> maybe_apply_function(fn metrics ->
      metrics
      |> List.flatten()
      |> MapSet.new()
      |> MapSet.intersection(@metrics_mapset)
      |> Enum.to_list()
    end)
  end

  @impl Sanbase.Metric.Behaviour
  def available_label_fqns(metric) do
    if metric in @fixed_labels_parameters_metrics_mapset do
      fixed_parameters = Map.get(@fixed_parameteres_map, metric)
      query_struct = available_label_fqns_query(metric, fixed_parameters)

      Sanbase.ClickhouseRepo.query_transform(query_struct, & &1)
      |> maybe_apply_function(&List.flatten/1)
    else
      {:ok, []}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def available_label_fqns(metric, %{slug: slug}) when is_binary(slug) do
    if metric in @fixed_labels_parameters_metrics_mapset do
      fixed_parameters = Map.get(@fixed_parameteres_map, metric)
      query_struct = available_label_fqns_query(metric, slug, fixed_parameters)

      Sanbase.ClickhouseRepo.query_transform(query_struct, & &1)
      |> maybe_apply_function(&List.flatten/1)
    else
      {:ok, []}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def available_slugs(), do: get_available_slugs()

  @impl Sanbase.Metric.Behaviour
  def available_slugs(metric)
      # otherwise age_distribution causes an infinite loop
      when metric in @histogram_metrics_name_list,
      do: HistogramMetric.available_slugs(metric)

  def available_slugs(metric), do: get_available_slugs(metric)

  @impl Sanbase.Metric.Behaviour
  def available_aggregations(), do: @aggregations

  @impl Sanbase.Metric.Behaviour
  def first_datetime(metric, selector) when metric in @histogram_metrics_name_list,
    do: HistogramMetric.first_datetime(metric, selector)

  def first_datetime(metric, selector) do
    first_datetime_query(metric, selector)
    |> ClickhouseRepo.query_transform(fn [datetime] ->
      DateTime.from_unix!(datetime)
    end)
    |> maybe_unwrap_ok_value()
  end

  @impl Sanbase.Metric.Behaviour
  def last_datetime_computed_at(metric, selector) when metric in @histogram_metrics_name_list,
    do: HistogramMetric.last_datetime_computed_at(metric, selector)

  def last_datetime_computed_at(metric, selector) do
    last_datetime_computed_at_query(metric, selector)
    |> ClickhouseRepo.query_transform(fn [datetime] ->
      DateTime.from_unix!(datetime)
    end)
    |> maybe_unwrap_ok_value()
  end

  # Private functions

  defp min_interval(metric), do: Map.get(@min_interval_map, metric)

  defp get_available_slugs() do
    available_slugs_query()
    |> ClickhouseRepo.query_transform(fn [slug] -> slug end)
  end

  defp get_available_slugs(metric) do
    available_slugs_for_metric_query(metric)
    |> ClickhouseRepo.query_transform(fn [slug] -> slug end)
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
    query_struct = aggregated_timeseries_data_query(metric, slugs, from, to, aggregation, filters)

    ClickhouseRepo.query_reduce(query_struct, %{}, fn [slug, value, has_changed], acc ->
      value = if has_changed == 1, do: value, else: nil
      Map.put(acc, slug, value)
    end)
  end

  defp get_filters(metric, opts) do
    # FIXME: Some of the `nft` metrics need additional filter for `owner=opensea`
    # to show correct values. Remove after fixed by bigdata.
    case String.starts_with?(metric, "nft_") and "owner" in Map.get(@selectors_map, metric) do
      true -> [owner: "opensea"]
      false -> Keyword.get(opts, :additional_filters, [])
    end
  end

  defp resolve_fixed_parameters(opts, metric) do
    case metric in @fixed_labels_parameters_metrics_mapset do
      true ->
        opts ++ [fixed_parameters: @fixed_parameteres_map[metric]]

      false ->
        opts
    end
  end
end
