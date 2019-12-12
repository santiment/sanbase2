defmodule Sanbase.MockPrice do
  import Mock

  @default_timeseries_data [
    [~U[2019-01-01 00:00:00Z] |> DateTime.to_unix(), 0.01, 100, 100_000, 50_000, 1],
    [~U[2019-01-02 00:00:00Z] |> DateTime.to_unix(), 0.02, 200, 200_000, 50_000, 1],
    [~U[2019-01-03 00:00:00Z] |> DateTime.to_unix(), 0.33, 300, 300_000, 50_000, 1],
    [~U[2019-01-04 00:00:00Z] |> DateTime.to_unix(), 0.04, 40, 40_000, 50_000, 1]
  ]

  def with_mock_timeseries_data(fun, data \\ @default_timeseries_data) do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ -> {:ok, %{rows: data}} end do
      fun.()
    end
  end
end
