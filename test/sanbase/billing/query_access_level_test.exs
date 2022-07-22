defmodule Sanbase.Billing.QueryAccessLevelTest do
  use ExUnit.Case, async: true

  # Assert that a query's access level does not change incidentally
  describe "subscription meta" do
    test "free queries defined in the schema" do
      free_queries =
        Sanbase.Billing.GraphqlSchema.get_queries_with_access_level(:free)
        |> Enum.sort()

      expected_free_queries =
        [
          :active_widgets,
          :address_historical_balance_change,
          :alerts_historical_activity,
          :alerts_stats,
          :all_currency_projects,
          :all_erc20_projects,
          :all_exchanges,
          :all_insights_by_search_term_highlighted,
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
          :api_metric_distribution_per_user,
          :api_metric_distribution,
          :assets_held_by_address,
          :blockchain_address_label_changes,
          :blockchain_address_labels,
          :blockchain_address_transaction_volume_over_time,
          :blockchain_address_user_pair,
          :blockchain_address,
          :chart_configuration,
          :chart_configurations,
          :check_annual_discount_eligibility,
          :comments_feed,
          :comments,
          :currencies_market_segments,
          :current_user,
          :daily_active_addresses,
          :dev_activity,
          :erc20_market_segments,
          :eth_fees_distribution,
          :eth_spent_by_all_projects,
          :eth_spent_by_erc20_projects,
          :eth_spent_over_time_by_all_projects,
          :eth_spent_over_time_by_erc20_projects,
          :featured_chart_configurations,
          :featured_insights,
          :featured_screeners,
          :featured_table_configurations,
          :featured_user_triggers,
          :featured_watchlists,
          :fetch_all_public_user_lists,
          :fetch_all_public_watchlists,
          :fetch_default_payment_instrument,
          :fetch_public_user_lists,
          :fetch_public_watchlists,
          :fetch_user_lists,
          :fetch_watchlists,
          :get_access_restrictions,
          :get_attributes_for_users,
          :get_auth_sessions,
          :get_available_blockchains,
          :get_available_clickhouse_tables,
          :get_available_metrics,
          :get_available_metrics_for_selector,
          :get_available_signals,
          :get_blockchain_address_labels,
          :get_chart_configuration_shared_access_token,
          :get_clickhouse_query_execution_stats,
          :get_coupon,
          :get_dashboard_cache,
          :get_dashboard_schema,
          :get_dashboard_schema_history,
          :get_dashboard_schema_history_list,
          :get_events_for_users,
          :get_full_url,
          :get_market_exchanges,
          :get_metric,
          :get_most_recent,
          :get_most_used,
          :get_most_voted,
          :get_nft_collection_by_contract,
          :get_nft_trades_count,
          :get_nft_trades,
          :get_primary_user,
          :get_raw_signals,
          :get_reports_by_tags,
          :get_reports,
          :get_secondary_users,
          :get_sheets_templates,
          :get_signal,
          :get_telegram_deep_link,
          :get_trigger_by_id,
          :get_user,
          :get_webinars,
          :github_activity,
          :github_availables_repos,
          :historical_balance,
          :historical_trigger_points,
          :history_price,
          :history_twitter_data,
          :incoming_transfers_summary,
          :insight_comments,
          :insight,
          :is_telegram_chat_id_valid,
          :ohlc,
          :outgoing_transfers_summary,
          :payments,
          :popular_insight_authors,
          :popular_search_terms,
          :post,
          :products_with_plans,
          :project_by_slug,
          :project,
          :projects_count,
          :projects_list_history_stats,
          :projects_list_stats,
          :public_triggers_for_user,
          :recent_transactions,
          :recent_transfers,
          :show_promoter,
          :signals_historical_activity,
          :social_volume_projects,
          :subcomments,
          :table_configuration,
          :table_configurations,
          :timeline_event,
          :timeline_events,
          :top_transfers,
          :transaction_volume_per_address,
          :twitter_data,
          :uniswap_value_distribution,
          :uniswap_who_claimed,
          :upcoming_invoice,
          :usd_value_address_change,
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
          :exchange_funds_flow,
          :get_latest_metric_data,
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
          :realtime_top_holders,
          :social_dominance,
          :social_gainers_losers_status,
          :social_volume,
          :token_age_consumed,
          :token_circulation,
          :token_velocity,
          :top_exchanges_by_balance,
          :top_holders_percent_of_total_supply,
          :top_holders,
          :top_social_gainers_losers,
          :topic_search,
          :transaction_volume,
          :word_context,
          :word_trend_score,
          :words_context,
          :words_social_volume
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
