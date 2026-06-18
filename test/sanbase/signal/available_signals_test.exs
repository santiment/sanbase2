defmodule Sanbase.Signal.AvailableSignalsTest do
  use ExUnit.Case, async: true

  test "available signals" do
    available_signals =
      Sanbase.Signal.available_signals()
      |> Enum.sort()

    expected_available_signals =
      [
        "anomaly_eth_whale_dump",
        "anomaly_hyperliquid_avg_funding_rate",
        "anomaly_large_stablecoin_mint",
        "anomaly_project_in_trending_words",
        "anomaly_social_price_correlation",
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
