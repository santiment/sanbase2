defmodule Sanbase.Pricing.SubscriptionMetaFieldTest do
  use ExUnit.Case, async: true

  # Assert that a query's subscription plan does not change incidentally
  describe "subscription meta" do
    test "there are no queries without defined subscription" do
      assert Sanbase.Pricing.Plan.AccessChecker.Helper.queries_without_subsciption_plan() == []
    end

    test "free queries" do
      free_queries =
        Sanbase.Pricing.Plan.AccessChecker.Helper.get_metrics_with_subscription_plan(:free)
        |> Enum.sort()

      expected_free_queries =
        [
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
          :emojis_sentiment,
          :fetch_all_public_user_lists,
          :projects_list_history_stats,
          :daily_active_addresses,
          :twitter_data,
          :github_availables_repos,
          :eth_spent_by_erc20_projects,
          :featured_insights,
          :insight,
          :current_poll,
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
          :watchlist
        ]
        |> Enum.sort()

      assert free_queries == expected_free_queries
    end

    test "basic queries" do
      basic_queries =
        Sanbase.Pricing.Plan.AccessChecker.Helper.get_metrics_with_subscription_plan(:basic)
        |> Enum.sort()

      expected_basic_queries =
        [
          :average_token_age_consumed_in_days,
          :burn_rate,
          :exchange_funds_flow,
          :exchange_volume,
          :gas_used,
          :miners_balance,
          :mining_pools_distribution,
          :network_growth,
          :percent_of_token_supply_on_exchanges,
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

    test "pro queries" do
      pro_queries =
        Sanbase.Pricing.Plan.AccessChecker.Helper.get_metrics_with_subscription_plan(:pro)
        |> Enum.sort()

      expected_pro_queries =
        [:daily_active_deposits, :mvrv_ratio, :nvt_ratio, :realized_value, :share_of_deposits]
        |> Enum.sort()

      assert pro_queries == expected_pro_queries
    end

    test "premium queries" do
      premium_queries =
        Sanbase.Pricing.Plan.AccessChecker.Helper.get_metrics_with_subscription_plan(:premium)
        |> Enum.sort()

      expected_premium_queries = []

      assert premium_queries == expected_premium_queries
    end

    test "restricted queries" do
      restricted_queries =
        Sanbase.Pricing.Plan.AccessChecker.Helper.get_metrics_with_subscription_plan(:restricted)
        |> Enum.sort()

      expected_restricted_queries =
        [:all_projects_project_transparency, :exchange_wallets] |> Enum.sort()

      assert restricted_queries == expected_restricted_queries
    end
  end
end
