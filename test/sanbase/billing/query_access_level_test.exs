defmodule Sanbase.Billing.QueryAccessLevelTest do
  use ExUnit.Case, async: true

  # Assert that a query's access level does not change incidentally
  describe "subscription meta" do
    test "free queries defined in the schema" do
      free_queries =
        Sanbase.Billing.ApiInfo.get_queries_with_access_level(:free)
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
          :featured_dashboards,
          :featured_queries,
          :fetch_all_public_user_lists,
          :fetch_all_public_watchlists,
          :fetch_default_payment_instrument,
          :fetch_public_user_lists,
          :fetch_public_watchlists,
          :fetch_user_lists,
          :fetch_watchlists,
          :generate_title_by_query,
          :get_access_restrictions,
          :get_auth_sessions,
          :get_available_blockchains,
          :get_available_metrics_for_selector,
          :get_available_metrics,
          :get_available_signals,
          :get_blockchain_address_labels,
          :get_cached_dashboard_queries_executions,
          :get_chart_configuration_shared_access_token,
          :get_clickhouse_database_metadata,
          :get_clickhouse_query_execution_stats,
          :get_current_user_submitted_twitter_handles,
          :get_coupon,
          :get_ecosystems,
          :get_events_for_users,
          :get_free_form_json,
          :get_full_url,
          :get_label_based_metric_owners,
          :get_market_exchanges,
          :get_menu,
          :get_metric,
          :get_metric_spike_explanations,
          :get_metric_spike_explanations_count,
          :get_metric_spike_explanations_metadata,
          :get_most_recent,
          :get_most_tweets,
          :get_most_used,
          :get_most_voted,
          :get_nft_collection_by_contract,
          :get_nft_trades_count,
          :get_nft_trades,
          :get_presigned_s3_url,
          :get_primary_user,
          :get_questionnaire_user_answers,
          :get_questionnaire,
          :get_raw_signals,
          :get_reports_by_tags,
          :get_reports,
          :get_secondary_users,
          :get_sheets_templates,
          :get_signal,
          :get_subscription_with_payment_intent,
          :get_telegram_deep_link,
          :get_trigger_by_id,
          :get_user_dashboards,
          :get_user,
          :get_webinars,
          :github_activity,
          :historical_balance,
          :historical_trigger_points,
          :history_price,
          :incoming_transfers_summary,
          :insight_comments,
          :insight,
          :is_telegram_chat_id_valid,
          :is_twitter_handle_monitored,
          :ohlc,
          :outgoing_transfers_summary,
          :payments,
          :popular_insight_authors,
          :popular_search_terms,
          :post,
          :ppp_settings,
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
          :social_dominance_trending_words,
          :social_volume_projects,
          :subcomments,
          :table_configuration,
          :table_configurations,
          :timeline_event,
          :timeline_events,
          :top_transfers,
          :transaction_volume_per_address,
          :upcoming_invoice,
          :usd_value_address_change,
          :user_list,
          :watchlist,
          :watchlist_by_slug,
          :words_social_dominance,
          :words_social_dominance_old,
          # Queries 2.0
          :get_dashboard,
          :get_sql_query,
          :get_public_queries,
          :get_query_executions,
          :get_user_queries,
          :run_dashboard_sql_query,
          :run_raw_sql_query,
          :run_sql_query,
          :get_cached_query_executions,
          :check_sanr_nft_subscription_eligibility,
          # UI Metrics metadata queries
          :get_categories_and_groups,
          :get_metrics_by_category,
          :get_metrics_by_category_and_group,
          :get_ordered_metrics,
          :get_recently_added_metrics
        ]
        |> Enum.sort()

      unexpected_free_queries = free_queries -- expected_free_queries
      assert unexpected_free_queries == []

      missing_free_queries = expected_free_queries -- free_queries
      assert missing_free_queries == []
    end

    test "restricted queries defined in the schema" do
      restricted_queries =
        Sanbase.Billing.ApiInfo.get_queries_with_access_level(:restricted)
        |> Enum.sort()

      expected_restricted_queries =
        [
          :gas_used,
          :get_latest_metric_data,
          :get_project_trending_history,
          :get_trending_words,
          :get_word_trending_history,
          :miners_balance,
          :percent_of_token_supply_on_exchanges,
          :realtime_top_holders,
          :top_exchanges_by_balance,
          :top_holders,
          :top_holders_percent_of_total_supply,
          :word_context,
          :word_trend_score,
          :words_context,
          :words_social_volume
        ]
        |> Enum.sort()

      unexpected_restricted_queries = restricted_queries -- expected_restricted_queries
      assert unexpected_restricted_queries == []

      missing_restricted_queries = expected_restricted_queries -- restricted_queries
      assert missing_restricted_queries == []
    end

    test "forbidden queries from the schema" do
      # Forbidden queries are acessible only by basic authorization
      forbidden_queries =
        Sanbase.Billing.ApiInfo.get_queries_with_access_level(:forbidden)
        |> Enum.sort()

      expected_forbidden_queries = []

      assert forbidden_queries == expected_forbidden_queries
    end
  end
end
