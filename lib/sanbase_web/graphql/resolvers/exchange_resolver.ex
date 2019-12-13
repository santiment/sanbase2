defmodule SanbaseWeb.Graphql.Resolvers.ExchangeResolver do
  require Logger

  import Sanbase.Utils.ErrorHandling,
    only: [maybe_handle_graphql_error: 2, handle_graphql_error: 4]

  alias Sanbase.Model.{ExchangeAddress, Infrastructure}
  alias Sanbase.Clickhouse.EthTransfers

  @doc ~s"List all exchanges"
  def all_exchanges(_root, %{slug: "ethereum"}, _resolution) do
    {:ok, ExchangeAddress.exchange_names_by_infrastructure(Infrastructure.get("ETH"))}
  end

  def all_exchanges(_root, %{slug: "bitcoin"}, _resolution) do
    {:ok, ExchangeAddress.exchange_names_by_infrastructure(Infrastructure.get("BTC"))}
  end

  def all_exchanges(_, _, _) do
    {:error, "Currently only ethereum and bitcoin exchanges are supported"}
  end

  @doc ~s"""
  Return the accumulated volume of all the exchange addresses belonging to a certain exchange
  """
  def exchange_volume(_root, %{exchange: exchange, from: from, to: to}, _resolution) do
    with {:ok, addresses} <- ExchangeAddress.addresses_for_exchange(exchange),
         {:ok, exchange_volume} <- EthTransfers.exchange_volume(addresses, from, to) do
      {:ok, exchange_volume}
    else
      error ->
        Logger.error("Error getting exchange volume for: #{exchange}. #{inspect(error)}")
        {:error, "Error getting exchange volume for: #{exchange}"}
    end
  end

  def last_exchange_market_depth(
        _root,
        %{exchange: exchange, ticker_pair: ticker_pair, limit: limit},
        _resolution
      ) do
    Sanbase.Clickhouse.Exchanges.MarketDepth.last_exchange_market_depth(
      exchange,
      ticker_pair,
      limit
    )
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(
        "Last exchange market depth",
        inspect(exchange) <> " and " <> inspect(ticker_pair),
        error,
        description: "exchange and ticker_pair"
      )
    end)
  end

  def last_exchange_trades(
        _root,
        %{exchange: exchange, ticker_pair: ticker_pair, limit: limit},
        _resolution
      ) do
    Sanbase.Clickhouse.Exchanges.Trades.last_exchange_trades(exchange, ticker_pair, limit)
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(
        "Last exchange trades",
        inspect(exchange) <> " and " <> inspect(ticker_pair),
        error,
        description: "exchange and ticker_pair"
      )
    end)
  end

  def exchange_trades(
        _root,
        %{exchange: exchange, ticker_pair: ticker_pair, from: from, to: to, interval: interval},
        _resolution
      ) do
    Sanbase.Clickhouse.Exchanges.Trades.exchange_trades(exchange, ticker_pair, from, to, interval)
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(
        "Aggregated exchange trades",
        inspect(exchange) <> " and " <> inspect(ticker_pair),
        error,
        description: "exchange and ticker_pair"
      )
    end)
  end

  def exchange_trades(
        _root,
        %{exchange: exchange, ticker_pair: ticker_pair, from: from, to: to},
        _resolution
      ) do
    Sanbase.Clickhouse.Exchanges.Trades.exchange_trades(exchange, ticker_pair, from, to)
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(
        "Exchange trades",
        inspect(exchange) <> " and " <> inspect(ticker_pair),
        error,
        description: "exchange and ticker_pair"
      )
    end)
  end

  def exchange_market_pair_slug_mapping(
        _root,
        %{exchange: exchange, ticker_pair: ticker_pair},
        _resolution
      ) do
    {from_slug, to_slug} =
      Sanbase.Exchanges.MarketPairMapping.get_slugs_pair_by(exchange, ticker_pair)

    {:ok, %{from_slug: from_slug, to_slug: to_slug}}
  end
end
