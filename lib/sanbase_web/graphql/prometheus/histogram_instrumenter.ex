defmodule SanbaseWeb.Graphql.Prometheus.HistogramInstrumenter do
  @moduledoc ~s"""
  Stores data about the queries that is used to build prometheus histograms
  https://prometheus.io/docs/practices/histograms/

  Each bucket's number represents milliseconds. A query with a runtime of X seconds
  falls in the last bucket with value Y where X < Y
  """
  use AbsintheMetrics,
    adapter: AbsintheMetrics.Backend.PrometheusHistogram,
    arguments: [
      buckets: [10, 50, 100, 200, 300, 400, 500, 700, 1000, 1500] ++ buckets(2000, 1000, 20)
    ]

  # Returns a list of `number` elements starting from `from` with a step `step`
  defp buckets(from, step, number) do
    Stream.unfold(from, fn x -> {x, x + step} end)
    |> Enum.take(number)
  end
end
