defmodule SanbaseWeb.Graphql.Prometheus.Instrumenter do
  use AbsintheMetrics,
    adapter: AbsintheMetrics.Backend.PrometheusHistogram,
    # See prometheus.ex for more examples
    arguments: [buckets: {:exponential, 250, 1.5, 7}]
end
