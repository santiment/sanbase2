defmodule Sanbase.Clickhouse.Metric do
  @table "daily_metrics_v2"

  @moduledoc ~s"""
  Provide access to the v2 metrics in Clickhouse

  The metrics are stored in the '#{@table}' clickhouse table where each metric
  is defined by a `metric_id` and every project is defined by an `asset_id`.
  """
  @behaviour Sanbase.Metric.Behaviour

  use Ecto.Schema

  import Sanbase.Clickhouse.Metric.Helper, only: [slug_asset_id_map: 0, asset_id_slug_map: 0]
  import Sanbase.Clickhouse.Metric.SqlQueries

  alias Sanbase.Clickhouse.Metric.LabelTemplate
  alias __MODULE__.FileHandler

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @metrics_file "available_v2_metrics.json"
  @external_resource Path.join(__DIR__, @metrics_file)

  @plain_aggregations FileHandler.aggregations()
  @aggregations [nil] ++ @plain_aggregations
  @timeseries_metrics_name_list FileHandler.metrics_with_data_type(:timeseries)
  @histogram_metrics_name_list FileHandler.metrics_with_data_type(:histogram)
  @access_map FileHandler.access_map()
  @min_interval_map FileHandler.min_interval_map()
  @free_metrics FileHandler.metrics_with_access(:free)
  @restricted_metrics FileHandler.metrics_with_access(:restricted)
  @aggregation_map FileHandler.aggregation_map()
  @human_readable_name_map FileHandler.human_readable_name_map()
  @metrics_data_type_map FileHandler.metrics_data_type_map()
  @metrics_label_map FileHandler.metrics_label_map()
  @metrics_name_list (@histogram_metrics_name_list ++
                        @timeseries_metrics_name_list)
                     |> Enum.uniq()

  @type slug :: String.t()
  @type metric :: String.t()
  @type interval :: String.t()

  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:asset_id, :integer)
    field(:metric_id, :integer)
    field(:value, :float)
    field(:computed_at, :utc_datetime)
  end

  @impl Sanbase.Metric.Behaviour
  def free_metrics(), do: @free_metrics

  @impl Sanbase.Metric.Behaviour
  def restricted_metrics(), do: @restricted_metrics

  @impl Sanbase.Metric.Behaviour
  def access_map(), do: @access_map

  @doc ~s"""
  Get a given metric for a slug and time range. The metric's aggregation
  function can be changed by the last optional parameter. The available
  aggregations are #{inspect(@plain_aggregations)}
  """
  @impl Sanbase.Metric.Behaviour
  def timeseries_data(metric, slug, from, to, interval, aggregation \\ nil)

  def timeseries_data(metric, slug, from, to, interval, aggregation) do
    aggregation = aggregation || Map.get(@aggregation_map, metric)
    {query, args} = timeseries_data_query(metric, slug, from, to, interval, aggregation)

    ClickhouseRepo.query_transform(query, args, fn [unix, value] ->
      %{
        datetime: DateTime.from_unix!(unix),
        value: value
      }
    end)
  end

  @impl Sanbase.Metric.Behaviour
  def histogram_data(metric, slug, from, to, interval, limit) do
    {query, args} = histogram_data_query(metric, slug, from, to, interval, limit)
    label_template = Map.get(@metrics_label_map, metric)

    ClickhouseRepo.query_reduce(
      query,
      args,
      %{labels: [], values: []},
      fn
        [unix, value], %{labels: labels, values: values} ->
          dt1 = unix |> DateTime.from_unix!()

          dt2 =
            [dt1 |> Timex.shift(seconds: Sanbase.DateTimeUtils.str_to_sec(interval)), to]
            |> Enum.min_by(&DateTime.to_unix/1)

          label =
            [dt1, dt2]
            |> Enum.map(&Timex.format!(&1, "%Y-%m-%d %H:%M %Z", :strftime))
            |> LabelTemplate.get(label_template)

          %{labels: [label | labels], values: [value | values]}
      end
    )
  end

  @impl Sanbase.Metric.Behaviour
  def aggregated_timeseries_data(metric, slug, from, to, aggregation \\ nil)

  def aggregated_timeseries_data(_metric, nil, _from, _to, _aggregation), do: {:ok, []}
  def aggregated_timeseries_data(_metric, [], _from, _to, _aggregation), do: {:ok, []}

  def aggregated_timeseries_data(_metric, _slug, _from, _to, aggregation)
      when aggregation not in @aggregations do
    {:error, "The aggregation '#{inspect(aggregation)}' is not supported"}
  end

  def aggregated_timeseries_data(metric, slug_or_slugs, from, to, aggregation)
      when is_binary(slug_or_slugs) or is_list(slug_or_slugs) do
    aggregation = aggregation || Map.get(@aggregation_map, metric)
    get_aggregated_timeseries_data(metric, slug_or_slugs |> List.wrap(), from, to, aggregation)
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
       data_type: Map.get(@metrics_data_type_map, metric)
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
  def available_metrics(), do: @metrics_name_list

  @impl Sanbase.Metric.Behaviour
  def available_slugs(), do: get_available_slugs()

  @impl Sanbase.Metric.Behaviour
  def available_slugs(_metric), do: get_available_slugs()

  @impl Sanbase.Metric.Behaviour
  def available_aggregations(), do: @aggregations

  @impl Sanbase.Metric.Behaviour
  def first_datetime(metric, slug) do
    {query, args} = first_datetime_query(metric, slug)

    ClickhouseRepo.query_transform(query, args, fn [datetime] ->
      DateTime.from_unix!(datetime)
    end)
    |> case do
      {:ok, [result]} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  # Private functions

  defp min_interval(metric), do: Map.get(@min_interval_map, metric)

  defp get_available_slugs() do
    {query, args} = available_slugs_query()

    ClickhouseRepo.query_transform(query, args, fn [slug] -> slug end)
  end

  defp get_aggregated_timeseries_data(metric, slugs, from, to, aggregation)
       when is_list(slugs) and length(slugs) > 20 do
    result =
      Enum.chunk_every(slugs, 20)
      |> Sanbase.Parallel.map(&get_aggregated_timeseries_data(metric, &1, from, to, aggregation),
        timeout: 25_000,
        max_concurrency: 8,
        ordered: false
      )
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.flat_map(&elem(&1, 1))

    {:ok, result}
  end

  defp get_aggregated_timeseries_data(metric, slugs, from, to, aggregation) when is_list(slugs) do
    {:ok, asset_map} = slug_asset_id_map()

    case Map.take(asset_map, slugs) |> Map.values() do
      [] ->
        {:ok, []}

      asset_ids ->
        {:ok, asset_id_map} = asset_id_slug_map()

        {query, args} = aggregated_timeseries_data_query(metric, asset_ids, from, to, aggregation)

        ClickhouseRepo.query_transform(query, args, fn [asset_id, value] ->
          %{slug: Map.get(asset_id_map, asset_id), value: value}
        end)
    end
  end
end
