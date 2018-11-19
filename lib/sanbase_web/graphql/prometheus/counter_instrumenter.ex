defmodule SanbaseWeb.Graphql.Prometheus.CounterInstrumenter do
  use AbsintheMetrics,
    adapter: SanbaseWeb.Graphql.Prometheus.CounterBackend
end
