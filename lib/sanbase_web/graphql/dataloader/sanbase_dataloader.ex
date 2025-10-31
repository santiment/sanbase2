defmodule SanbaseWeb.Graphql.SanbaseDataloader do
  alias SanbaseWeb.Graphql.BalanceDataloader
  alias SanbaseWeb.Graphql.ClickhouseDataloader
  alias SanbaseWeb.Graphql.EcosystemDataloader
  alias SanbaseWeb.Graphql.LabelsDataloader
  alias SanbaseWeb.Graphql.MetricshubDataloader
  alias SanbaseWeb.Graphql.PostgresDataloader
  alias SanbaseWeb.Graphql.PriceDataloader

  @spec data() :: Dataloader.KV.t()
  def data() do
    Dataloader.KV.new(&query/2)
  end

  @metricshub_dataloader [
    :social_documents_by_ids
  ]
  @labels_dataloader [
    :address_labels
  ]

  @clickhouse_dataloader [
    :average_daily_active_addresses,
    :average_dev_activity,
    :eth_spent,
    :aggregated_metric,
    :project_info
  ]

  @balance_dataloader [
    :address_selector_current_balance,
    :address_selector_balance_change,
    :eth_balance
  ]

  @price_dataloader [
    :volume_change_24h,
    :last_price_usd
  ]

  @postgres_comments_dataloader [
    # comment entity id
    :comment_blockchain_address_id,
    :comment_chart_configuration_id,
    :comment_dashboard_id,
    :comment_insight_id,
    :comment_short_url_id,
    :comment_timeline_event_id,
    :comment_watchlist_id,
    # Comments count
    :blockchain_addresses_comments_count,
    :chart_configuration_comments_count,
    :dashboard_comments_count,
    :insights_comments_count,
    :short_urls_comments_count,
    :timeline_events_comments_count,
    :watchlist_comments_count,
    # Votes
    :chart_configuration_vote_stats,
    :chart_configuration_voted_at,
    :dashboard_vote_stats,
    :dashboard_voted_at,
    :query_vote_stats,
    :query_voted_at,
    :insight_vote_stats,
    :insight_voted_at,
    :timeline_event_vote_stats,
    :timeline_event_voted_at,
    :user_trigger_vote_stats,
    :user_trigger_voted_at,
    :watchlist_vote_stats,
    :watchlist_voted_at
  ]

  @postgres_dataloader [
    :current_user_address_details,
    :infrastructure,
    :insights_count_per_user,
    :market_segments,
    :project_by_slug,
    :traded_on_exchanges_count,
    :traded_on_exchanges,
    :social_volume_query,
    # Users
    :users_by_id,
    # Founders
    :available_founders_per_slug,
    # Contract addresses
    :main_contract_address,
    :contract_addresses,
    :eth_addresses,
    :source_slug_mappings
    # Trending Words
  ]

  @postgres_dataloader @postgres_dataloader ++ @postgres_comments_dataloader

  @ecosystem_dataloader [:ecosystem_aggregated_metric_data, :ecosystem_timeseries_metric_data]

  @postgres_dataloader MapSet.new(@postgres_dataloader)
  @clickhouse_dataloader MapSet.new(@clickhouse_dataloader)

  def query(queryable, args) do
    cond do
      queryable in @clickhouse_dataloader ->
        ClickhouseDataloader.query(queryable, args)

      queryable in @postgres_dataloader ->
        PostgresDataloader.query(queryable, args)

      queryable in @balance_dataloader ->
        BalanceDataloader.query(queryable, args)

      queryable in @price_dataloader ->
        PriceDataloader.query(queryable, args)

      queryable in @metricshub_dataloader ->
        MetricshubDataloader.query(queryable, args)

      queryable in @ecosystem_dataloader ->
        EcosystemDataloader.query(queryable, args)

      queryable in @labels_dataloader ->
        LabelsDataloader.query(queryable, args)

      true ->
        raise(RuntimeError, "Unknown queryable provided to the dataloder: #{inspect(queryable)}")
    end
  end
end
