defmodule Sanbase.Signal.AvailableSignalsTest do
  use ExUnit.Case, async: true

  test "available signals" do
    available_signals =
      Sanbase.Signal.available_signals()
      |> Enum.sort()

    expected_available_signals =
      [
        "ath",
        "dai_mint",
        "anomaly_stack_circulation_1d",
        "anomaly_mvrv_usd_1d",
        "anomaly_mvrv_usd_7d",
        "anomaly_mvrv_usd_30d",
        "anomaly_mvrv_usd_60d",
        "anomaly_mvrv_usd_90d",
        "anomaly_mvrv_usd_180d",
        "anomaly_mvrv_usd_365d",
        "anomaly_mvrv_usd_2y",
        "anomaly_mvrv_usd_3y",
        "anomaly_mvrv_usd_5y",
        "anomaly_mvrv_usd_10y",
        "anomaly_mvrv_usd",
        "anomaly_transaction_volume",
        "anomaly_daily_active_addresses",
        "anomaly_network_growth",
        "anomaly_token_velocity",
        "anomaly_stack_age_consumed",
        "anomaly_payment_count",
        "anomaly_exchange_token_supply",
        "anomaly_transaction_count",
        "anomaly_stack_cumulative_age_consumed",
        "anomaly_active_deposits",
        "anomaly_active_withdrawals",
        "old_coins_moved",
        "large_transactions",
        "mcd_art_liquidations",
        "large_exchange_deposit",
        "large_exchange_withdrawal"
      ]
      |> Enum.sort()

    assert available_signals == expected_available_signals
  end
end
