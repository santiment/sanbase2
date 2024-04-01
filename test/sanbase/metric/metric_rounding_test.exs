defmodule Sanbase.MetricRoundingTest do
  use Sanbase.DataCase

  test "data is rounded up to 6 decimals" do
    # Define this in a separate file to avoid conflicts with the global setup_all mock
    # in the metric_test.exs
    rows = [
      # rounded to 6 decimal digits
      [1_711_756_800, 830_224.712938719283719280],
      # does not change
      [1_711_843_200, 696_766.0123],
      # Should be rounded to just .1
      [1_711_929_600, 469_393.100000000003]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      {:ok, data} =
        Sanbase.Metric.timeseries_data(
          "daily_active_addresses",
          %{slug: "bitcoin"},
          ~U[2024-03-31 00:00:00Z],
          ~U[2024-04-01 23:59:59Z],
          "1d"
        )

      assert data == [
               %{value: 830_224.712939, datetime: ~U[2024-03-30 00:00:00Z]},
               %{value: 696_766.0123, datetime: ~U[2024-03-31 00:00:00Z]},
               %{value: 469_393.1, datetime: ~U[2024-04-01 00:00:00Z]}
             ]
    end)
  end
end
