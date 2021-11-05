defmodule SanbaseWeb.Graphql.SanbaseDataloader do
  alias SanbaseWeb.Graphql.{
    BalanceDataloader,
    ClickhouseDataloader,
    LabelsDataloader,
    PostgresDataloader,
    PriceDataloader
  }

  @spec data() :: Dataloader.KV.t()
  def data() do
    Dataloader.KV.new(&query/2)
  end

  @labels_dataloader [
    :address_labels
  ]

  @clickhouse_dataloader [
    :average_daily_active_addresses,
    :average_dev_activity,
    :eth_spent,
    :aggregated_metric
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
    :comment_insight_id,
    :comment_short_url_id,
    :comment_timeline_event_id,
    :comment_wallet_hunter_proposal_id,
    :comment_watchlist_id,
    # Comments count
    :blockchain_addresses_comments_count,
    :chart_configuration_comments_count,
    :insights_comments_count,
    :short_urls_comments_count,
    :timeline_events_comments_count,
    :wallet_hunters_proposals_comments_count,
    :watchlist_comments_count,
    # Users
    :users_no_preload
  ]
  @postgres_dataloader [
    :current_user_address_details,
    :infrastructure,
    :insights_count_per_user,
    :market_segment,
    :project_by_slug,
    :traded_on_exchanges_count,
    :traded_on_exchanges
  ]

  @postgres_dataloader @postgres_dataloader ++ @postgres_comments_dataloader

  def query(queryable, args) do
    cond do
      queryable in @labels_dataloader ->
        LabelsDataloader.query(queryable, args)

      queryable in @clickhouse_dataloader ->
        ClickhouseDataloader.query(queryable, args)

      queryable in @balance_dataloader ->
        BalanceDataloader.query(queryable, args)

      queryable in @price_dataloader ->
        PriceDataloader.query(queryable, args)

      queryable in @postgres_dataloader ->
        PostgresDataloader.query(queryable, args)

      true ->
        raise(RuntimeError, "Unknown queryable provided to the dataloder: #{inspect(queryable)}")
    end
  end
end
