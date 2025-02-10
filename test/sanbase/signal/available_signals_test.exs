defmodule Sanbase.Signal.AvailableSignalsTest do
  use ExUnit.Case, async: true

  test "available signals" do
    available_signals = Enum.sort(Sanbase.Signal.available_signals())

    expected_available_signals =
      Enum.sort([
        "anomaly_active_deposits",
        "anomaly_active_withdrawals",
        "anomaly_age_consumed",
        "anomaly_circulation_1d",
        "anomaly_cumulative_age_consumed",
        "anomaly_daily_active_addresses",
        "anomaly_mvrv_usd_10y",
        "anomaly_mvrv_usd_180d",
        "anomaly_mvrv_usd_1d",
        "anomaly_mvrv_usd_2y",
        "anomaly_mvrv_usd_30d",
        "anomaly_mvrv_usd_365d",
        "anomaly_mvrv_usd_3y",
        "anomaly_mvrv_usd_5y",
        "anomaly_mvrv_usd_60d",
        "anomaly_mvrv_usd_7d",
        "anomaly_mvrv_usd_90d",
        "anomaly_mvrv_usd",
        "anomaly_network_growth",
        "anomaly_payment_count",
        "anomaly_supply_on_exchanges",
        "anomaly_transaction_count",
        "anomaly_transaction_volume",
        "anomaly_velocity",
        "dai_mint",
        "large_exchange_deposit",
        "large_exchange_withdrawal",
        "large_transactions",
        "mcd_art_liquidations",
        "old_coins_moved",
        "price_usd_all_time_high",
        "project_in_trending_words",
        "mvrv_usd_30d_upper_zone",
        "mvrv_usd_60d_upper_zone",
        "mvrv_usd_180d_upper_zone",
        "mvrv_usd_365d_upper_zone",
        "mvrv_usd_30d_lower_zone",
        "mvrv_usd_60d_lower_zone",
        "mvrv_usd_180d_lower_zone",
        "mvrv_usd_365d_lower_zone"
      ])

    assert available_signals == expected_available_signals
  end
end
