defmodule Sanbase.Billing.MetricAccessLevelTest do
  use ExUnit.Case, async: true

  # Assert that a query's access level does not change incidentally
  test "there are no queries without defined subscription" do
    assert Sanbase.Billing.GraphqlSchema.get_all_without_access_level() == []
  end

  test "free metrics" do
    free_queries =
      Sanbase.Billing.GraphqlSchema.get_metrics_with_access_level(:free)
      |> Enum.sort()

    expected_free_queries =
      [
        "active_addresses_24h",
        "daily_active_addresses",
        "daily_avg_marketcap_usd",
        "daily_avg_price_usd",
        "daily_closing_marketcap_usd",
        "daily_closing_price_usd",
        "daily_high_price_usd",
        "daily_low_price_usd",
        "daily_opening_price_usd",
        "daily_trading_volume_usd",
        "dev_activity",
        "github_activity",
        "dev_activity_contributors_count",
        "github_activity_contributors_count",
        "marketcap_usd",
        "price_btc",
        "price_usd",
        "volume_usd",
        # change metrics
        "volume_usd_change_1d",
        "volume_usd_change_7d",
        "volume_usd_change_30d",
        "price_usd_change_1d",
        "price_usd_change_7d",
        "price_usd_change_30d",
        "active_addresses_24h_change_1d",
        "active_addresses_24h_change_7d",
        "active_addresses_24h_change_30d"
      ]
      |> Enum.sort()

    assert free_queries == expected_free_queries
  end

  test "restricted metrics" do
    restricted_metrics =
      Sanbase.Billing.GraphqlSchema.get_metrics_with_access_level(:restricted)
      |> Enum.sort()

    metrics = [
      "mean_realized_price_usd",
      "mean_realized_price_usd_10y",
      "mean_realized_price_usd_5y",
      "mean_realized_price_usd_3y",
      "mean_realized_price_usd_2y",
      "mean_realized_price_usd_365d",
      "mean_realized_price_usd_180d",
      "mean_realized_price_usd_90d",
      "mean_realized_price_usd_60d",
      "mean_realized_price_usd_30d",
      "mean_realized_price_usd_7d",
      "mean_realized_price_usd_1d",
      "mvrv_long_short_diff_usd",
      "mvrv_usd",
      "mvrv_usd_10y",
      "mvrv_usd_5y",
      "mvrv_usd_3y",
      "mvrv_usd_2y",
      "mvrv_usd_365d",
      "mvrv_usd_180d",
      "mvrv_usd_90d",
      "mvrv_usd_60d",
      "mvrv_usd_30d",
      "mvrv_usd_7d",
      "mvrv_usd_1d",
      "circulation",
      "circulation_10y",
      "circulation_5y",
      "circulation_3y",
      "circulation_2y",
      "circulation_365d",
      "circulation_180d",
      "circulation_90d",
      "circulation_60d",
      "circulation_30d",
      "circulation_7d",
      "circulation_1d",
      "mean_age",
      "mean_dollar_invested_age",
      "realized_value_usd",
      "realized_value_usd_10y",
      "realized_value_usd_5y",
      "realized_value_usd_3y",
      "realized_value_usd_2y",
      "realized_value_usd_365d",
      "realized_value_usd_180d",
      "realized_value_usd_90d",
      "realized_value_usd_60d",
      "realized_value_usd_30d",
      "realized_value_usd_7d",
      "realized_value_usd_1d",
      "velocity",
      "transaction_volume",
      "exchange_inflow",
      "exchange_outflow",
      "exchange_balance",
      "age_destroyed",
      "nvt",
      "nvt_transaction_volume",
      "network_growth",
      "active_deposits",
      "active_withdrawals",
      "withdrawal_transactions",
      # social metrics
      "community_messages_count_discord",
      "community_messages_count_telegram",
      "community_messages_count_total",
      "social_dominance_discord",
      "social_dominance_professional_traders_chat",
      "social_dominance_reddit",
      "social_dominance_telegram",
      "social_dominance_total",
      "social_volume_discord",
      "social_volume_professional_traders_chat",
      "social_volume_reddit",
      "social_volume_telegram",
      "social_volume_total",
      # histogram metrics
      "age_distribution",
      "price_histogram",
      # exchange supply metrics
      "exchange_token_supply"
    ]

    expected_result = metrics |> Enum.sort()

    # The diff algorithm fails to nicely print that a single metric is
    # missing but instead shows some not-understandable result when comparing
    # the lists directly

    # not present in expected
    assert MapSet.difference(MapSet.new(restricted_metrics), MapSet.new(expected_result))
           |> Enum.to_list() == []

    # not present in the metrics list
    assert MapSet.difference(MapSet.new(expected_result), MapSet.new(restricted_metrics))
           |> Enum.to_list() == []
  end

  test "extension needed metrics" do
    # Forbidden queries are acessible only by basic authorization
    extension_metrics =
      Sanbase.Billing.GraphqlSchema.get_metrics_with_access_level(:extension)
      |> Enum.sort()

    assert extension_metrics == []
  end

  test "forbidden metrics" do
    forbidden_metrics =
      Sanbase.Billing.GraphqlSchema.get_metrics_with_access_level(:forbidden)
      |> Enum.sort()

    expected_forbidden_metrics =
      []
      |> Enum.sort()

    assert forbidden_metrics == expected_forbidden_metrics
  end
end
