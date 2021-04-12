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
        "anomalies_stack_circulation_1d",
        "anomalies_mvrv_usd_1d",
        "anomalies_mvrv_usd_7d",
        "anomalies_mvrv_usd_30d",
        "anomalies_mvrv_usd_60d",
        "anomalies_mvrv_usd_90d",
        "anomalies_mvrv_usd_180d",
        "anomalies_mvrv_usd_365d",
        "anomalies_mvrv_usd_2y",
        "anomalies_mvrv_usd_3y",
        "anomalies_mvrv_usd_5y",
        "anomalies_mvrv_usd_10y",
        "anomalies_mvrv_usd",
        "anomalies_transaction_volume",
        "anomalies_daily_active_addresses",
        "anomalies_network_growth",
        "anomalies_token_velocity",
        "anomalies_stack_age_consumed",
        "anomalies_payment_count",
        "anomalies_exchange_token_supply",
        "anomalies_transaction_count",
        "anomalies_stack_cumulative_age_consumed",
        "anomalies_active_deposits",
        "anomalies_active_withdrawals",
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
