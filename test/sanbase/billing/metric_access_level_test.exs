defmodule Sanbase.Billing.MetricAccessLevelTest do
  use ExUnit.Case, async: true

  # Assert that a query's access level does not change incidentally
  test "there are no queries without defined subscription" do
    assert Sanbase.Billing.GraphqlSchema.get_all_without_access_level() == []
  end

  test "free metrics" do
    free_metrics =
      Sanbase.Billing.GraphqlSchema.get_metrics_with_access_level(:free)
      |> Enum.sort()

    expected_free_metrics =
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
        "dev_activity_1d",
        "30d_moving_avg_dev_activity_change_1d",
        "github_activity",
        "dev_activity_contributors_count",
        "github_activity_contributors_count",
        "marketcap_usd",
        "price_btc",
        "price_usd",
        "price_eth",
        "price_usd_5m",
        "volume_usd",
        "twitter_followers",
        # change metrics
        "volume_usd_change_1d",
        "volume_usd_change_7d",
        "volume_usd_change_30d",
        "price_usd_change_1d",
        "price_usd_change_7d",
        "price_usd_change_30d",
        "active_addresses_24h_change_1d",
        "active_addresses_24h_change_7d",
        "active_addresses_24h_change_30d",
        "dev_activity_change_1d",
        "dev_activity_change_7d",
        "dev_activity_change_30d",
        "marketcap_usd_change_1d",
        "marketcap_usd_change_7d",
        "marketcap_usd_change_30d"
      ]
      |> Enum.sort()

    assert free_metrics == expected_free_metrics
  end

  test "restricted metrics" do
    restricted_metrics =
      Sanbase.Billing.GraphqlSchema.get_metrics_with_access_level(:restricted)
      |> Enum.sort()

    expected_restricted_metrics =
      [
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
        # mvrv Metrics
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
        "mvrv_usd_intraday",
        "mvrv_usd_intraday_10y",
        "mvrv_usd_intraday_5y",
        "mvrv_usd_intraday_3y",
        "mvrv_usd_intraday_2y",
        "mvrv_usd_intraday_365d",
        "mvrv_usd_intraday_180d",
        "mvrv_usd_intraday_90d",
        "mvrv_usd_intraday_60d",
        "mvrv_usd_intraday_30d",
        "mvrv_usd_intraday_7d",
        "mvrv_usd_intraday_1d",
        # circulation metrics
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
        # dormant ciruclation
        "dormant_circulation_10y",
        "dormant_circulation_5y",
        "dormant_circulation_3y",
        "dormant_circulation_2y",
        "dormant_circulation_365d",
        "dormant_circulation_180d",
        "dormant_circulation_90d",
        # other
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
        "transaction_volume_usd",
        "exchange_inflow",
        "exchange_outflow",
        "exchange_balance",
        "age_consumed",
        "age_destroyed",
        "nvt",
        "nvt_transaction_volume",
        "network_growth",
        "active_deposits",
        "deposit_transactions",
        "active_withdrawals",
        "withdrawal_transactions",
        "payments_count",
        "transactions_count",
        "fees",
        "network_circulation_usd_1d",
        "fees_to_network_circulation_usd_1d",
        # social metrics
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
        "social_volume_twitter",
        "social_volume_bitcointalk",
        "social_volume_telegram",
        "social_volume_total",
        "sentiment_positive_telegram",
        "sentiment_positive_discord",
        "sentiment_positive_reddit",
        "sentiment_positive_twitter",
        "sentiment_positive_bitcointalk",
        "sentiment_positive_professional_traders_chat",
        "sentiment_positive_total",
        "sentiment_negative_telegram",
        "sentiment_negative_discord",
        "sentiment_negative_reddit",
        "sentiment_negative_twitter",
        "sentiment_negative_bitcointalk",
        "sentiment_negative_professional_traders_chat",
        "sentiment_negative_total",
        "sentiment_balance_telegram",
        "sentiment_balance_discord",
        "sentiment_balance_reddit",
        "sentiment_balance_twitter",
        "sentiment_balance_bitcointalk",
        "sentiment_balance_professional_traders_chat",
        "sentiment_balance_total",
        "sentiment_volume_consumed_telegram",
        "sentiment_volume_consumed_discord",
        "sentiment_volume_consumed_reddit",
        "sentiment_volume_consumed_twitter",
        "sentiment_volume_consumed_bitcointalk",
        "sentiment_volume_consumed_professional_traders_chat",
        "sentiment_volume_consumed_total",
        # histogram metrics
        "age_distribution",
        "price_histogram",
        "spent_coins_cost",
        "all_spent_coins_cost",
        # exchange supply metrics
        "supply_on_exchanges",
        "supply_outside_exchanges",
        "percent_of_total_supply_on_exchanges",
        # top holders metrics
        "amount_in_top_holders",
        "amount_in_exchange_top_holders",
        "amount_in_non_exchange_top_holders",
        # holders distribution metrics
        "holders_distribution_0.001_to_0.01",
        "holders_distribution_0.01_to_0.1",
        "holders_distribution_0.1_to_1",
        "holders_distribution_0_to_0.001",
        "holders_distribution_100_to_1k",
        "holders_distribution_100k_to_1M",
        "holders_distribution_10M_to_inf",
        "holders_distribution_10_to_100",
        "holders_distribution_10k_to_100k",
        "holders_distribution_1M_to_10M",
        "holders_distribution_1_to_10",
        "holders_distribution_1k_to_10k",
        "holders_distribution_combined_balance_0.001_to_0.01",
        "holders_distribution_combined_balance_0.01_to_0.1",
        "holders_distribution_combined_balance_0.1_to_1",
        "holders_distribution_combined_balance_0_to_0.001",
        "holders_distribution_combined_balance_100_to_1k",
        "holders_distribution_combined_balance_100k_to_1M",
        "holders_distribution_combined_balance_10M_to_inf",
        "holders_distribution_combined_balance_10_to_100",
        "holders_distribution_combined_balance_10k_to_100k",
        "holders_distribution_combined_balance_1M_to_10M",
        "holders_distribution_combined_balance_1_to_10",
        "holders_distribution_combined_balance_1k_to_10k",
        "holders_distribution_total",
        "holders_distribution_over_1",
        "holders_distribution_over_10",
        "holders_distribution_over_100",
        "holders_distribution_over_1k",
        "holders_distribution_over_10k",
        "holders_distribution_over_100k",
        "holders_distribution_over_1M",
        "holders_distribution_combined_balance_over_1",
        "holders_distribution_combined_balance_over_10",
        "holders_distribution_combined_balance_over_100",
        "holders_distribution_combined_balance_over_1k",
        "holders_distribution_combined_balance_over_10k",
        "holders_distribution_combined_balance_over_100k",
        "holders_distribution_combined_balance_over_1M",
        "percent_of_holders_distribution_combined_balance_0_to_0.001",
        "percent_of_holders_distribution_combined_balance_0.001_to_0.01",
        "percent_of_holders_distribution_combined_balance_0.01_to_0.1",
        "percent_of_holders_distribution_combined_balance_0.1_to_1",
        "percent_of_holders_distribution_combined_balance_1_to_10",
        "percent_of_holders_distribution_combined_balance_10_to_100",
        "percent_of_holders_distribution_combined_balance_100_to_1k",
        "percent_of_holders_distribution_combined_balance_1k_to_10k",
        "percent_of_holders_distribution_combined_balance_10k_to_100k",
        "percent_of_holders_distribution_combined_balance_100k_to_1M",
        "percent_of_holders_distribution_combined_balance_1M_to_10M",
        "percent_of_holders_distribution_combined_balance_10M_to_inf",
        # makerdao metrics
        "dai_created",
        "dai_repaid",
        "mcd_collat_ratio",
        "mcd_collat_ratio_sai",
        "mcd_collat_ratio_weth",
        "mcd_dsr",
        "mcd_erc20_supply",
        "mcd_locked_token",
        "mcd_stability_fee",
        "mcd_supply",
        "scd_collat_ratio",
        "scd_locked_token",
        "stock_to_flow",
        # derivatives
        "bitmex_perpetual_funding_rate",
        "bitmex_perpetual_basis",
        "bitmex_perpetual_open_interest",
        "bitmex_perpetual_open_value",
        "bitmex_perpetual_basis_ratio",
        "bitmex_perpetual_price",
        "bitmex_composite_price_index",
        # label metrics
        "active_deposits_per_exchange",
        "active_withdrawals_per_exchange",
        "deposit_transactions_per_exchange",
        "exchange_balance_per_exchange",
        "exchange_inflow_per_exchange",
        "exchange_outflow_per_exchange",
        "withdrawal_transactions_per_exchange",
        # Defi
        "defi_total_value_locked_eth",
        "defi_total_value_locked_usd",
        # Change metrics
        "network_growth_change_1d",
        "network_growth_change_7d",
        "network_growth_change_30d"
      ]
      |> Enum.sort()

    # The diff algorithm fails to nicely print that a single metric is
    # missing but instead shows some not-understandable result when comparing
    # the lists directly

    # not present in expected
    assert MapSet.difference(
             MapSet.new(restricted_metrics),
             MapSet.new(expected_restricted_metrics)
           )
           |> Enum.to_list() == []

    # not present in the metrics list
    assert MapSet.difference(
             MapSet.new(expected_restricted_metrics),
             MapSet.new(restricted_metrics)
           )
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
