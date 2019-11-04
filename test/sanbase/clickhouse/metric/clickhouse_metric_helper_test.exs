defmodule Sanbase.Clickhouse.Metric.HelperTest do
  use Sanbase.DataCase

  import Mock

  test "metric id to name map correctly uses the version" do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [1, "daily_active_addresses", "2019-01-01"],
             [2, "daily_active_addresses", "2019-11-03"]
           ]
         }}
      end do
      {:ok, version_map} = Sanbase.Clickhouse.Metric.Helper.metric_name_id_map()
      assert {"daily_active_addresses", 1} in version_map
      refute {"daily_active_addresses", 2} in version_map
    end
  end
end
