defmodule Sanbase.Clickhouse.MetricAdapter.HelperTest do
  use Sanbase.DataCase

  test "metric id to name map" do
    rows = [
      [1, "daily_active_addresses"],
      [2, "nvt"]
    ]

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      {:ok, map} = Sanbase.Clickhouse.MetadataHelper.metric_name_to_metric_id_map()

      assert {"daily_active_addresses", 1} in map
      assert {"nvt", 2} in map
    end)
  end
end
