defmodule SanbaseWeb.Graphql.SanbaseDataloader do
  alias SanbaseWeb.Graphql.{
    BalanceDataloader,
    ClickhouseDataloader,
    MetricPostgresDataloader,
    ParityDataloader,
    PriceDataloader
  }

  @spec data() :: Dataloader.KV.t()
  def data() do
    Dataloader.KV.new(&query/2)
  end

  @spec query(
          :aggregated_metric
          | :average_daily_active_addresses
          | :average_dev_activity
          | :blockchain_addresses_comments_count
          | :comment_blockchain_address_id
          | :comment_insight_id
          | :comment_short_url_id
          | :comment_timeline_event_id
          | :address_selector_current_balance
          | :eth_balance
          | :eth_spent
          | :infrastructure
          | :insights_comments_count
          | :insights_count_per_user
          | :market_segment
          | :project_by_slug
          | :short_urls_comments_count
          | :timeline_events_comments_count
          | :volume_change_24h
          | {:price, any()},
          any()
        ) :: {:error, String.t()} | {:ok, float()} | map()
  def query(queryable, args) do
    case queryable do
      x
      when x in [
             :average_daily_active_addresses,
             :average_dev_activity,
             :eth_spent,
             :aggregated_metric
           ] ->
        ClickhouseDataloader.query(queryable, args)

      x
      when x in [
             :address_selector_current_balance,
             :address_selector_balance_change
           ] ->
        BalanceDataloader.query(queryable, args)

      :volume_change_24h ->
        PriceDataloader.query(queryable, args)

      {:price, _} ->
        PriceDataloader.query(queryable, args)

      :eth_balance ->
        ParityDataloader.query(queryable, args)

      x
      when x in [
             :comment_insight_id,
             :comment_timeline_event_id,
             :comment_blockchain_address_id,
             :comment_short_url_id,
             :infrastructure,
             :market_segment,
             :insights_comments_count,
             :insights_count_per_user,
             :timeline_events_comments_count,
             :blockchain_addresses_comments_count,
             :short_urls_comments_count,
             :project_by_slug
           ] ->
        MetricPostgresDataloader.query(queryable, args)
    end
  end
end
