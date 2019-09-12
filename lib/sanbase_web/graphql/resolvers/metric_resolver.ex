defmodule SanbaseWeb.Graphql.Resolvers.MetricResolver do
  require Logger

  import SanbaseWeb.Graphql.Helpers.Utils, only: [calibrate_interval: 7]

  alias Sanbase.Clickhouse.Metric

  @datapoints 300

  def get_metric(_root, %{metric: metric}, _resolution), do: {:ok, %{metric: metric}}
  def get_available_metrics(_root, _args, _resolution), do: Metric.available_metrics()
  def get_available_slugs(_root, _args, _resolution), do: Metric.available_slugs()
  def get_metadata(%{}, _args, %{source: %{metric: metric}}), do: Metric.metadata(metric)
  def available_since(_root, %{slug: slug}, _), do: Metric.first_datetime(slug)

  def get_timeseries_data(
        _root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        %{source: %{metric: metric}}
      ) do
    with {:ok, from, to, interval} <-
           calibrate_interval(Metric, slug, from, to, interval, 86_400, @datapoints) do
      Metric.get(metric, slug, from, to, interval, Map.get(args, :aggregation))
    end
  end
end
