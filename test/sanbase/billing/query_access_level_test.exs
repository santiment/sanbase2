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
          :active_widgets,
          :all_currency_projects,
          :all_erc20_projects,
          :all_exchanges,
          :all_insights_by_search_term,
          :all_insights_by_tag,
          :all_insights_for_user,
          :all_insights_user_voted,
          :all_insights,
          :all_market_segments,
          :all_projects_by_function,
          :all_projects_by_ticker,
          :all_projects,
          :all_public_triggers,
          :all_tags,
          :assets_held_by_address,
          :chart_configuration,
          :chart_configurations,
          :currencies_market_segments,
          :current_user,
          :daily_active_addresses,
          :dev_activity,
          :erc20_market_segments,
          :eth_spent_by_all_projects,
          :eth_spent_by_erc20_projects,
          :eth_spent_over_time_by_all_projects,
          :eth_spent_over_time_by_erc20_projects,
          :exchange_market_pair_to_slugs,
          :exchange_trades,
          :featured_chart_configurations,
          :featured_insights,
          :featured_table_configurations,
          :featured_user_triggers,
          :featured_watchlists,
          :fetch_all_public_user_lists,
          :fetch_all_public_watchlists,
          :fetch_public_user_lists,
          :fetch_public_watchlists,
          :fetch_user_lists,
          :fetch_watchlists,
          :get_access_restrictions,
          :get_anomaly,
          :get_available_anomalies,
          :get_available_metrics,
          :get_coupon,
          :get_full_url,
          :get_metric,
          :get_telegram_deep_link,
          :get_trigger_by_id,
          :get_user,
          :github_activity,
          :github_availables_repos,
          :historical_balance,
          :historical_trigger_points,
          :history_price,
          :history_twitter_data,
          :insight,
          :last_exchange_market_depth,
          :last_exchange_trades,
          :metric_anomaly,
          :news,
          :ohlc,
          :payments,
          :popular_insight_authors,
          :popular_search_terms,
          :post,
          :price_volume_diff,
          :products_with_plans,
          :project_by_slug,
          :project,
          :projects_count,
          :projects_list_history_stats,
          :projects_list_stats,
          :public_triggers_for_user,
          :show_promoter,
          :signals_historical_activity,
          :slugs_to_exchange_market_pair,
          :social_volume_projects,
          :table_configuration,
          :table_configurations,
          :timeline_event,
          :timeline_events,
          :twitter_data,
          :twitter_mention_count,
          :user_list,
          :watchlist,
          :watchlist_by_slug
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

    test "forbidden queries from the schema" do
      # Forbidden queries are acessible only by basic authorization
      forbidden_queries =
        Sanbase.Billing.GraphqlSchema.get_queries_with_access_level(:forbidden)
        |> Enum.sort()

      expected_forbidden_queries = []

      assert forbidden_queries == expected_forbidden_queries
    end

    test "extension needed queries from the schema" do
      # Forbidden queries are acessible only by basic authorization
      pro_queries =
        Sanbase.Billing.GraphqlSchema.get_queries_with_access_level(:extension)
        |> Enum.sort()

      expected_pro_queries =
        [:exchange_wallets]
        |> Enum.sort()

      assert pro_queries == expected_pro_queries
    end
  end
end
