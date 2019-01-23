defmodule SanbaseWeb.Graphql.SanbaseDataloader do
  alias SanbaseWeb.Graphql.ClickhouseDataloader
  alias SanbaseWeb.Graphql.InfluxdbDataloader
  alias SanbaseWeb.Graphql.TimescaledbDataloader
  alias SanbaseWeb.Graphql.ParityDataloader

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
          | {:price, any()},
          any()
        ) :: {:error, <<_::64, _::_*8>>} | {:ok, float()} | map()
  def query(queryable, args) do
    case queryable do
      x when x in [:average_dev_activity, :eth_spent] ->
        ClickhouseDataloader.query(queryable, args)

      :volume_change_24h ->
        InfluxdbDataloader.query(queryable, args)

      {:price, _} ->
        InfluxdbDataloader.query(queryable, args)

      :average_daily_active_addresses ->
        TimescaledbDataloader.query(queryable, args)

      :eth_balance ->
        ParityDataloader.query(queryable, args)
    end
  end
end
