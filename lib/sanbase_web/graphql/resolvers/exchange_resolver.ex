defmodule SanbaseWeb.Graphql.Resolvers.ExchangeResolver do
  require Logger

  alias Sanbase.Model.ExchangeAddress
  alias Sanbase.Clickhouse.EthTransfers

  @doc ~s"List all exchanges"
  def all_exchanges(_root, _args, _resolution) do
    {:ok, ExchangeAddress.exchange_names()}
  end

  @doc ~s"""
  Return the accumulated volume of all the exchange addresses belonging to a certain exchange
  """
  def exchange_volume(_root, %{exchange: exchange, from: from, to: to}, _resolution) do
    with {:ok, addresses} <- ExchangeAddress.addresses_for_exchange(exchange),
         {:ok, exchange_volume} = EthTransfers.exchange_volume(addresses, from, to) do
      {:ok, exchange_volume}
    else
      error ->
        Logger.error("Error getting exchange volume for: #{exchange}. #{inspect(error)}")
        {:error, "Error getting exchange volume for: #{exchange}"}
    end
  end
end
