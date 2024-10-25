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
  alias __MODULE__.Registry

  @default_complexity_weight 0.3

  @type slug :: String.t()
  @type metric :: String.t()
  @type interval :: String.t()

  defguard is_supported_selector(s)
           when is_map(s) and
                  (is_map_key(s, :slug) or is_map_key(s, :address) or
                     is_map_key(s, :contract_address))

  @impl Sanbase.Metric.Behaviour
  def incomplete_metrics(), do: Registry.incomplete_metrics()

  @impl Sanbase.Metric.Behaviour
  def free_metrics(), do: Registry.metrics_list_with_access(:free)

  @impl Sanbase.Metric.Behaviour
  def restricted_metrics(), do: Registry.metrics_list_with_access(:restricted)

  @impl Sanbase.Metric.Behaviour
  def fixed_labels_parameters_metrics(), do: Registry.fixed_labels_parameters_metrics_list()

  @impl Sanbase.Metric.Behaviour
  def deprecated_metrics_map(), do: Registry.deprecated_metrics_map()

  @impl Sanbase.Metric.Behaviour
  def soft_deprecated_metrics_map(), do: Registry.soft_deprecated_metrics_map()

  @impl Sanbase.Metric.Behaviour
  def access_map(), do: Registry.access_map()

  @impl Sanbase.Metric.Behaviour
  def min_plan_map(), do: Registry.min_plan_map()

  @impl Sanbase.Metric.Behaviour
  def has_incomplete_data?(metric), do: Map.get(Registry.incomplete_data_map(), metric)

  @impl Sanbase.Metric.Behaviour
  def complexity_weight(_), do: @default_complexity_weight

  @impl Sanbase.Metric.Behaviour
  def broken_data(_metric, _selector, _from, _to), do: {:ok, []}

  @doc ~s"""
  Get a given metric for a slug and time range. The metric's aggregation
  function can be changed by the last optional parameter
  """
  @impl Sanbase.Metric.Behaviour
  def timeseries_data(_metric, %{slug: []}, _from, _to, _interval, _opts), do: {:ok, []}

  def timeseries_data(metric, selector, from, to, interval, opts)
      when is_supported_selector(selector) do
    aggregation =
      Keyword.get(opts, :aggregation, nil) || Map.get(Registry.aggregation_map(), metric)

    opts = resolve_fixed_parameters(opts, metric)
    filters = get_filters(metric, opts)

    [
      metric,
      selector,
      filters,
      opts
    ]

    timeseries_data_query(metric, selector, from, to, interval, aggregation, filters, opts)
    |> exec_timeseries_data_query()
  end

  @impl Sanbase.Metric.Behaviour
  def timeseries_data_per_slug(metric, %{slug: slug}, from, to, interval, opts) do
    aggregation =
      Keyword.get(opts, :aggregation, nil) || Map.get(Registry.aggregation_map(), metric)

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
    aggregation =
      Keyword.get(opts, :aggregation, nil) || Map.get(Registry.aggregation_map(), metric)

    filters = Keyword.get(opts, :additional_filters, [])
    slugs = List.wrap(slug_or_slugs)
    get_aggregated_timeseries_data(metric, slugs, from, to, aggregation, filters)
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_by_filter(metric, from, to, operator, threshold, opts) do
    aggregation =
      Keyword.get(opts, :aggregation, nil) || Map.get(Registry.aggregation_map(), metric)

    filters = Keyword.get(opts, :additional_filters, [])

    slugs_by_filter_query(metric, from, to, operator, threshold, aggregation, filters)
    |> ClickhouseRepo.query_transform(fn [slug, _value] -> slug end)
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_order(metric, from, to, direction, opts) do
    aggregation =
      Keyword.get(opts, :aggregation, nil) || Map.get(Registry.aggregation_map(), metric)

    filters = Keyword.get(opts, :additional_filters, [])

    slugs_order_query(metric, from, to, direction, aggregation, filters)
    |> ClickhouseRepo.query_transform(fn [slug, _value] -> slug end)
  end

  @impl Sanbase.Metric.Behaviour
  def required_selectors(), do: FileHandler.required_selectors_map()

  @impl Sanbase.Metric.Behaviour
  def metadata(metric) do
    min_interval = min_interval(metric)
    default_aggregation = Map.get(Registry.aggregation_map(), metric)
    is_label_fqn_metric = :label_fqn in Map.get(Registry.selectors_map(), metric, [])

    {:ok,
     %{
       metric: metric,
       internal_metric: Map.get(Registry.name_to_metric_map(), metric, metric),
       has_incomplete_data: has_incomplete_data?(metric),
       min_interval: min_interval,
       default_aggregation: default_aggregation,
       available_aggregations: Registry.aggregations(),
       available_selectors: Map.get(Registry.selectors_map(), metric),
       required_selectors: Map.get(Registry.required_selectors_map(), metric, []),
       data_type: Map.get(Registry.metrics_data_type_map(), metric),
       is_timebound: Map.get(Registry.timebound_flag_map(), metric),
       complexity_weight: @default_complexity_weight,
       docs: Map.get(Registry.docs_links_map(), metric),
       is_deprecated: false,
       hard_deprecate_after: nil,
       is_label_fqn_metric: is_label_fqn_metric
     }}
  end

  @impl Sanbase.Metric.Behaviour
  def human_readable_name(metric) do
    {:ok, Map.get(Registry.human_readable_name_map(), metric)}
  end

  @doc ~s"""
  Return a list of available metrics.
  """

  @impl Sanbase.Metric.Behaviour
  def available_histogram_metrics(), do: Registry.metrics_list_with_data_type(:histogram)
  @impl Sanbase.Metric.Behaviour
  def available_timeseries_metrics(), do: Registry.metrics_list_with_data_type(:timeseries)

  @impl Sanbase.Metric.Behaviour
  def available_table_metrics(), do: Registry.metrics_list_with_data_type(:table)

  @impl Sanbase.Metric.Behaviour
  def available_metrics(), do: Registry.metrics_list()

  @impl Sanbase.Metric.Behaviour
  def available_metrics(selector) do
    available_metrics_for_selector_query(selector)
    |> ClickhouseRepo.query_transform(fn [metric] ->
      Map.get(Registry.metric_to_names_map(), metric)
    end)
    |> maybe_apply_function(fn metrics ->
      metrics
      |> List.flatten()
      |> MapSet.new()
      |> MapSet.intersection(Registry.metrics_mapset())
      |> Enum.to_list()
    end)
  end

  @impl Sanbase.Metric.Behaviour
  def available_label_fqns(metric) do
    cond do
      metric in Registry.fixed_labels_parameters_metrics_mapset() ->
        fixed_parameters = Map.get(Registry.fixed_parameters_map(), metric)
        query_struct = available_label_fqns_for_fixed_parameters_query(metric, fixed_parameters)

        Sanbase.ClickhouseRepo.query_transform(query_struct, & &1)
        |> maybe_apply_function(&List.flatten/1)

      Map.get(Registry.table_map(), metric) == "labeled_intraday_metrics_v2" ->
        query_struct = available_label_fqns_for_labeled_intraday_metrics_query(metric)
        Sanbase.ClickhouseRepo.query_transform(query_struct, & &1)

      true ->
        {:ok, []}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def available_label_fqns(metric, %{slug: slug}) when is_binary(slug) do
    cond do
      metric in Registry.fixed_labels_parameters_metrics_mapset() ->
        fixed_parameters = Map.get(Registry.fixed_parameters_map(), metric)

        query_struct =
          available_label_fqns_for_fixed_parameters_query(metric, slug, fixed_parameters)

        Sanbase.ClickhouseRepo.query_transform(query_struct, & &1)
        |> maybe_apply_function(&List.flatten/1)

      Map.get(Registry.table_map(), metric) == "labeled_intraday_metrics_v2" ->
        query_struct = available_label_fqns_for_labeled_intraday_metrics_query(metric, slug)
        Sanbase.ClickhouseRepo.query_transform(query_struct, & &1)

      true ->
        {:ok, []}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def available_slugs(), do: get_available_slugs()

  @impl Sanbase.Metric.Behaviour
  def available_slugs(metric) do
    cond do
      metric in Registry.metrics_mapset_with_data_type(:histogram) ->
        # otherwise age_distribution causes an infinite loop
        HistogramMetric.available_slugs(metric)

      true ->
        get_available_slugs(metric)
    end
  end

  @impl Sanbase.Metric.Behaviour
  def available_aggregations(), do: Registry.aggregations_with_nil()

  @impl Sanbase.Metric.Behaviour
  def first_datetime(metric, selector) do
    cond do
      metric in Registry.metrics_mapset_with_data_type(:histogram) ->
        HistogramMetric.first_datetime(metric, selector)

      true ->
        first_datetime_query(metric, selector)
        |> ClickhouseRepo.query_transform(fn [datetime] -> DateTime.from_unix!(datetime) end)
        |> maybe_unwrap_ok_value()
    end
  end

  @impl Sanbase.Metric.Behaviour
  def last_datetime_computed_at(metric, selector) do
    cond do
      metric in Registry.metrics_mapset_with_data_type(:histogram) ->
        HistogramMetric.last_datetime_computed_at(metric, selector)

      true ->
        last_datetime_computed_at_query(metric, selector)
        |> ClickhouseRepo.query_transform(fn [datetime] -> DateTime.from_unix!(datetime) end)
        |> maybe_unwrap_ok_value()
    end
  end

  # Private functions

  defp min_interval(metric), do: Map.get(Registry.min_interval_map(), metric)

  defp get_available_slugs() do
    available_slugs_query()
    |> ClickhouseRepo.query_transform(fn [slug] -> slug end)
  end

  defp get_available_slugs(metric) do
    available_slugs_for_metric_query(metric)
    |> ClickhouseRepo.query_transform(fn [slug] -> slug end)
  end

  defp get_aggregated_timeseries_data(metric, slugs, from, to, aggregation, filters)
       when is_list(slugs) and length(slugs) > 1000 do
    result =
      Enum.chunk_every(slugs, 1000)
      |> Sanbase.Parallel.map(
        &get_aggregated_timeseries_data(metric, &1, from, to, aggregation, filters),
        timeout: 55_000,
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
    case String.starts_with?(metric, "nft_") and
           "owner" in Map.get(Registry.selectors_map(), metric) do
      true -> [owner: "opensea"]
      false -> Keyword.get(opts, :additional_filters, [])
    end
  end

  defp resolve_fixed_parameters(opts, metric) do
    cond do
      metric in Registry.fixed_labels_parameters_metrics_mapset() ->
        opts ++ [fixed_parameters: Map.get(Registry.fixed_parameters_map(), metric)]

      true ->
        opts
    end
  end
end
