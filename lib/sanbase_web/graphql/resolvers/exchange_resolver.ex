defmodule SanbaseWeb.Graphql.Resolvers.ExchangeResolver do
  require Logger

  import Sanbase.Utils.ErrorHandling,
    only: [maybe_handle_graphql_error: 2, handle_graphql_error: 4]

  alias Sanbase.Clickhouse.ExchangeAddress
  alias Sanbase.Clickhouse.Exchanges

  @doc ~s"List all exchanges"
  def all_exchanges(_root, %{slug: slug} = args, _resolution) do
    ExchangeAddress.exchange_names(slug, Map.get(args, :is_dex, nil))
  end

  def top_exchanges_by_balance(
        _root,
        %{slug: slug} = args,
        _resolution
      ) do
    limit = Map.get(args, :limit, 100)

    opts =
      case Map.split(args, [:owner, :label]) do
        {map, _rest} when map_size(map) -> [additional_filters: Keyword.new(map)]
        _ -> []
      end

    Exchanges.ExchangeMetric.top_exchanges_by_balance(slug, limit, opts)
  end

  def last_exchange_market_depth(
        _root,
        %{exchange: exchange, ticker_pair: ticker_pair, limit: limit},
        _resolution
      ) do
    Exchanges.MarketDepth.last_exchange_market_depth(
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
    Exchanges.Trades.last_exchange_trades(exchange, ticker_pair, limit)
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
    Exchanges.Trades.exchange_trades(exchange, ticker_pair, from, to, interval)
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
    Exchanges.Trades.exchange_trades(exchange, ticker_pair, from, to)
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(
        "Exchange trades",
        inspect(exchange) <> " and " <> inspect(ticker_pair),
        error,
        description: "exchange and ticker_pair"
      )
    end)
  end

  def exchange_market_pair_to_slugs(
        _root,
        %{exchange: exchange, ticker_pair: ticker_pair},
        _resolution
      ) do
    result = Sanbase.Exchanges.MarketPairMapping.get_slugs_pair_by(exchange, ticker_pair) || %{}

    {:ok, result}
  end

  def slugs_to_exchange_market_pair(
        _root,
        %{exchange: exchange, from_slug: from_slug, to_slug: to_slug},
        _resolution
      ) do
    result =
      Sanbase.Exchanges.MarketPairMapping.slugs_to_exchange_market_pair(
        exchange,
        from_slug,
        to_slug
      ) || %{}

    {:ok, result}
  end
end
