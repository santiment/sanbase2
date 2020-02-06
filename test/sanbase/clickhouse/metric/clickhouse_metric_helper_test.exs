defmodule Sanbase.Clickhouse.Metric.HelperTest do
  use Sanbase.DataCase

  import Mock

  test "metric id to name map" do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [1, "daily_active_addresses"],
             [2, "dev_activity"]
           ]
         }}
      end do
      {:ok, map} = Sanbase.Clickhouse.MetadataHelper.metric_name_to_metric_id_map()

      assert {"daily_active_addresses", 1} in map
      assert {"dev_activity", 2} in map
    end
  end
end
