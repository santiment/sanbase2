defmodule SanbaseWeb.Graphql.SanbaseDataloader do
  alias SanbaseWeb.Graphql.{
    BalanceDataloader,
    ClickhouseDataloader,
    LabelsDataloader,
    PostgresDataloader,
    ParityDataloader,
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
    :address_selector_balance_change
  ]

  @price_dataloader [
    :volume_change_24h,
    :last_price_usd
  ]

  @parity_dataloader [:eth_balance]

  @postgres_dataloader [
    :blockchain_addresses_comments_count,
    :comment_blockchain_address_id,
    :comment_insight_id,
    :comment_proposal_id,
    :comment_short_url_id,
    :comment_timeline_event_id,
    :infrastructure,
    :insights_comments_count,
    :insights_count_per_user,
    :market_segment,
    :project_by_slug,
    :short_urls_comments_count,
    :timeline_events_comments_count,
    :user_address_details,
    :wallet_hunters_proposals_comments_count
  ]

  def query(queryable, args) do
    case queryable do
      x when x in @labels_dataloader ->
        LabelsDataloader.query(queryable, args)

      x when x in @clickhouse_dataloader ->
        ClickhouseDataloader.query(queryable, args)

      x when x in @balance_dataloader ->
        BalanceDataloader.query(queryable, args)

      x when x in @price_dataloader ->
        PriceDataloader.query(queryable, args)

      x when x in @parity_dataloader ->
        ParityDataloader.query(queryable, args)

      x when x in @postgres_dataloader ->
        PostgresDataloader.query(queryable, args)
    end
  end
end
