defmodule Sanbase.Signal.AvailableSignalsTest do
  use ExUnit.Case, async: true

  test "available signals" do
    available_signals =
      Sanbase.Signal.available_signals()
      |> Enum.sort()

    expected_available_signals =
      [
        "anomaly_project_in_trending_words",
        "anomaly_total_liquidations",
        "mvrv_usd_30d_upper_zone",
        "mvrv_usd_60d_upper_zone",
        "mvrv_usd_180d_upper_zone",
        "mvrv_usd_365d_upper_zone",
        "mvrv_usd_30d_lower_zone",
        "mvrv_usd_60d_lower_zone",
        "mvrv_usd_180d_lower_zone",
        "mvrv_usd_365d_lower_zone"
      ]
      |> Enum.sort()

    assert available_signals == expected_available_signals
  end
end
