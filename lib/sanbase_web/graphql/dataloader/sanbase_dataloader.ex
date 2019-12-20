defmodule SanbaseWeb.Graphql.SanbaseDataloader do
  alias SanbaseWeb.Graphql.ClickhouseDataloader
  alias SanbaseWeb.Graphql.InfluxdbDataloader
  alias SanbaseWeb.Graphql.ParityDataloader
  alias SanbaseWeb.Graphql.PostgresDataloader

  @spec data() :: Dataloader.KV.t()
  def data() do
    Dataloader.KV.new(&query/2)
  end

  @spec query(
          :average_daily_active_addresses
          | :average_dev_activity
          | :eth_balance
          | :eth_spent
          | :volume_change_24h
          | {:price, any()}
          | :market_segment
          | :infrastructure
          | :comment_insight_id
          | :project_transparency_status,
          any()
        ) :: {:error, String.t()} | {:ok, float()} | map()
  def query(queryable, args) do
    case queryable do
      x when x in [:average_daily_active_addresses, :average_dev_activity, :eth_spent] ->
        ClickhouseDataloader.query(queryable, args)

      :volume_change_24h ->
        InfluxdbDataloader.query(queryable, args)

      {:price, _} ->
        InfluxdbDataloader.query(queryable, args)

      :eth_balance ->
        ParityDataloader.query(queryable, args)

      x
      when x in [
             :comment_insight_id,
             :infrastructure,
             :market_segment,
             :project_transparency_status,
             :comments_count
           ] ->
        PostgresDataloader.query(queryable, args)
    end
  end
end
