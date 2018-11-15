defmodule SanbaseWeb.Graphql.Prometheus.HistogramInstrumenter do
  use AbsintheMetrics,
    adapter: AbsintheMetrics.Backend.PrometheusHistogram,
    arguments: [buckets: {:exponential, 10, 2, 12}]
end
