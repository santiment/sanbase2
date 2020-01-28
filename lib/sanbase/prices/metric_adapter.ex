defmodule Sanbase.Price.MetricAdapter do
  @behaviour Sanbase.Metric.Behaviour
  alias Sanbase.Price

  @aggregations [:any, :sum, :avg, :min, :max, :last, :first, :median]

  @timeseries_metrics ["price_usd", "price_btc", "volume_usd", "marketcap_usd"]
  @histogram_metrics []

  @metrics @histogram_metrics ++ @timeseries_metrics

  @access_map Enum.into(@metrics, %{}, fn metric -> {metric, :free} end)

  @free_metrics Enum.filter(@access_map, fn {_, level} -> level == :free end) |> Keyword.keys()
  @restricted_metrics Enum.filter(@access_map, fn {_, level} -> level == :restricted end)
                      |> Keyword.keys()

  @impl Sanbase.Metric.Behaviour
  def has_incomplete_data?(_), do: false

  @impl Sanbase.Metric.Behaviour
  def timeseries_data(metric, slug, from, to, interval, aggregation) do
    Price.timeseries_metric_data(slug, metric, from, to, interval, aggregation: aggregation)
  end

  @impl Sanbase.Metric.Behaviour
  def aggregated_timeseries_data(metric, slug, from, to, aggregation) do
    Price.aggregated_metric_timeseries_data(slug, metric, from, to, aggregation: aggregation)
  end

  @impl Sanbase.Metric.Behaviour
  def first_datetime(_metric, slug) do
    Price.first_datetime(slug)
  end

  @impl Sanbase.Metric.Behaviour
  def last_datetime_computed_at(_metric, slug) do
    Price.last_datetime_computed_at(slug)
  end

  @impl Sanbase.Metric.Behaviour
  def metadata(metric) do
    {:ok,
     %{
       metric: metric,
       min_interval: "5m",
       default_aggregation: :last,
       available_aggregations: @aggregations,
       data_type: :timeseries
     }}
  end

  @impl Sanbase.Metric.Behaviour
  def human_readable_name(metric) do
    case metric do
      "price_usd" -> {:ok, "Price in USD"}
      "price_btc" -> {:ok, "Price in BTC"}
      "marketcap_usd" -> {:ok, "Marketcap in USD"}
      "volume_usd" -> {:ok, "Volume in USd"}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def available_aggregations(), do: @aggregations

  @impl Sanbase.Metric.Behaviour
  def available_timeseries_metrics(), do: @timeseries_metrics

  @impl Sanbase.Metric.Behaviour
  def available_histogram_metrics(), do: @histogram_metrics

  @impl Sanbase.Metric.Behaviour
  def available_metrics(), do: @metrics

  @impl Sanbase.Metric.Behaviour
  def available_slugs() do
    Sanbase.Cache.get_or_store({:slugs_with_prices, 1800}, fn ->
      Price.available_slugs()
    end)
  end

  @impl Sanbase.Metric.Behaviour
  def available_slugs(metric) when metric in @metrics do
    available_slugs()
  end

  @impl Sanbase.Metric.Behaviour
  def free_metrics(), do: @free_metrics

  @impl Sanbase.Metric.Behaviour
  def restricted_metrics(), do: @restricted_metrics

  @impl Sanbase.Metric.Behaviour
  def access_map(), do: @access_map
end
