defmodule Sanbase.Billing.QueryAccessLevelTest do
  use ExUnit.Case, async: true

  # Assert that a query's access level does not change incidentally
  describe "subscription meta" do
    test "there are no queries without defined subscription" do
      assert Sanbase.Billing.GraphqlSchema.get_all_without_access_level() == []
    end

    test "free queries defined in the schema" do
      free_queries =
        Sanbase.Billing.GraphqlSchema.get_queries_with_access_level(:free)
        |> Enum.sort()

      expected_free_queries =
        [
          :get_coupon,
          :get_trigger_by_id,
          :payments,
          :current_user,
          :news,
          :project,
          :historical_balance,
          :elasticsearch_stats,
          :historical_trigger_points,
          :price_volume_diff,
          :assets_held_by_address,
          :social_volume_projects,
          :all_market_segments,
          :get_telegram_deep_link,
          :products_with_plans,
          :projects_count,
          :ohlc,
          :all_insights_for_user,
          :history_twitter_data,
          :all_insights_user_voted,
          :all_exchanges,
          :eth_spent_over_time_by_erc20_projects,
          :history_price,
          :metric_anomaly,
          :fetch_all_public_watchlists,
          :public_triggers_for_user,
          :post,
          :projects_list_stats,
          :all_public_triggers,
          :currencies_market_segments,
          :twitter_mention_count,
          :all_currency_projects,
          :featured_user_triggers,
          :timeline_events,
          :all_insights,
          :featured_watchlists,
          :signals_historical_activity,
          :erc20_market_segments,
          :github_activity,
          :fetch_public_user_lists,
          :project_by_slug,
          :fetch_public_watchlists,
          :all_tags,
          :fetch_all_public_user_lists,
          :projects_list_history_stats,
          :daily_active_addresses,
          :twitter_data,
          :github_availables_repos,
          :eth_spent_by_erc20_projects,
          :featured_insights,
          :insight,
          :all_projects_by_function,
          :eth_spent_by_all_projects,
          :fetch_user_lists,
          :all_erc20_projects,
          :fetch_watchlists,
          :all_projects,
          :eth_spent_over_time_by_all_projects,
          :all_insights_by_tag,
          :user_list,
          :dev_activity,
          :watchlist,
          :watchlist_by_slug,
          :get_available_metrics,
          :get_available_anomalies,
          :get_metric,
          :get_anomaly,
          :get_user,
          :all_projects_by_ticker,
          :last_exchange_market_depth,
          :last_exchange_trades,
          :exchange_trades,
          :exchange_market_pair_to_slugs,
          :slugs_to_exchange_market_pair
        ]
        |> Enum.sort()

      assert free_queries == expected_free_queries
    end

    test "free metrics" do
      free_queries =
        Sanbase.Billing.GraphqlSchema.get_metrics_with_access_level(:free)
        |> Enum.sort()

      expected_free_queries =
        [
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
          "marketcap_usd",
          "price_btc",
          "price_usd",
          "volume_usd"
        ]
        |> Enum.sort()

      assert free_queries == expected_free_queries
    end

    test "restricted queries defined in the schema" do
      basic_queries =
        Sanbase.Billing.GraphqlSchema.get_queries_with_access_level(:restricted)
        |> Enum.sort()

      expected_basic_queries =
        [
          :average_token_age_consumed_in_days,
          :burn_rate,
          :daily_active_deposits,
          :emojis_sentiment,
          :exchange_funds_flow,
          :exchange_volume,
          :gas_used,
          :get_project_trending_history,
          :get_word_trending_history,
          :get_trending_words,
          :miners_balance,
          :mining_pools_distribution,
          :mvrv_ratio,
          :network_growth,
          :nvt_ratio,
          :percent_of_token_supply_on_exchanges,
          :realized_value,
          :share_of_deposits,
          :social_dominance,
          :social_gainers_losers_status,
          :social_volume,
          :token_age_consumed,
          :token_circulation,
          :token_velocity,
          :top_holders_percent_of_total_supply,
          :top_social_gainers_losers,
          :topic_search,
          :transaction_volume,
          :trending_words,
          :word_context,
          :word_trend_score
        ]
        |> Enum.sort()

      assert basic_queries == expected_basic_queries
    end

    test "restricted metrics" do
      restricted_queries =
        Sanbase.Billing.GraphqlSchema.get_metrics_with_access_level(:restricted)
        |> Enum.sort()

      added_with_metric_adapter = [
        "discord_social_dominance",
        "discord_social_volume",
        "reddit_social_dominance",
        "telegram_social_dominance",
        "telegram_social_volume"
      ]

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
        "age_distribution"
      ]

      expected_metrics =
        (added_with_metric_adapter ++ metrics)
        |> Enum.uniq()
        |> Enum.sort()

      # The diff algorithm fails to nicely print that a single metric is
      # missing but instead shows some not-understandable result when comparing
      # the lists directly
      assert MapSet.difference(MapSet.new(restricted_queries), MapSet.new(expected_metrics))
             |> Enum.to_list() == []

      assert MapSet.difference(MapSet.new(expected_metrics), MapSet.new(restricted_queries))
             |> Enum.to_list() == []
    end

    test "forbidden queries from the schema" do
      # Forbidden queries are acessible only by basic authorization
      forbidden_queries =
        Sanbase.Billing.GraphqlSchema.get_queries_with_access_level(:forbidden)
        |> Enum.sort()

      expected_forbidden_queries =
        [:all_projects_project_transparency]
        |> Enum.sort()

      assert forbidden_queries == expected_forbidden_queries
    end

    test "extension needed queries from the schema" do
      # Forbidden queries are acessible only by basic authorization
      pro_queries =
        Sanbase.Billing.GraphqlSchema.get_queries_with_access_level(:extension)
        |> Enum.sort()

      expected_pro_queries =
        [:exchange_wallets, :all_exchange_wallets]
        |> Enum.sort()

      assert pro_queries == expected_pro_queries
    end

    test "forbidden metrics" do
      forbidden_metrics =
        Sanbase.Billing.GraphqlSchema.get_metrics_with_access_level(:forbidden)
        |> Enum.sort()

      expected_forbidden_metrics = [] |> Enum.sort()

      assert forbidden_metrics == expected_forbidden_metrics
    end
  end
end
