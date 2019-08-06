defmodule SanbaseWeb.Graphql.Resolvers.MetricResolver do
  require Logger

  alias Sanbase.Clickhouse.Metric

  def get_timeseries_metric(
        _root,
        %{
          metric: metric,
          slug: slug,
          from: from,
          to: to,
          interval: interval
        } = args,
        _resolution
      ) do
    Metric.get(metric, slug, from, to, interval, Map.get(args, :aggregation))
  end
end
