defmodule Sanbase.Clickhouse.MetricAdapter.HistogramMetricTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Clickhouse.MetricAdapter.HistogramMetric

  test "staking pool valuations are returned as integers" do
    from = ~U[2026-11-01 00:00:00Z]
    to = ~U[2026-11-03 00:00:00Z]
    rows = [[DateTime.to_unix(from), [{"Lido", 120.0}, {"Coinbase", 0.0}]]]

    {:ok, [point]} =
      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        HistogramMetric.histogram_data(
          "eth2_staking_pools_validators_count_over_time",
          %{slug: "ethereum"},
          from,
          to,
          "1d",
          10
        )
      end)

    assert point.value === [
             %{staking_pool: "Lido", valuation: 120},
             %{staking_pool: "Coinbase", valuation: 0}
           ]
  end
end
