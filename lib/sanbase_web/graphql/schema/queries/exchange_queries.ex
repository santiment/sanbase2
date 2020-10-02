defmodule SanbaseWeb.Graphql.Schema.ExchangeQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias SanbaseWeb.Graphql.Middlewares.AccessControl
  alias SanbaseWeb.Graphql.Resolvers.ExchangeResolver

  object :exchange_queries do
    field :top_exchanges_by_balance, list_of(:top_exchange_balance) do
      meta(access: :restricted)

      arg(:slug, non_null(:string))
      arg(:label, list_of(:string))
      arg(:owner, list_of(:string))
      arg(:limit, :integer, default_value: 100)

      middleware(AccessControl)

      cache_resolve(&ExchangeResolver.top_exchanges_by_balance/3)
    end

    @desc ~s"""
    Returns last market depth calculations for given exchange and ticker pair
    """
    field :last_exchange_market_depth, list_of(:exchange_market_depth) do
      meta(access: :free)

      arg(:exchange, non_null(:string))
      arg(:ticker_pair, non_null(:string))
      arg(:limit, non_null(:integer), default_value: 100)

      cache_resolve(&ExchangeResolver.last_exchange_market_depth/3)
    end

    @desc ~s"""
    Returns last trades for given exchange and ticker pair
    """
    field :last_exchange_trades, list_of(:exchange_trade) do
      meta(access: :free)

      arg(:exchange, non_null(:string))
      arg(:ticker_pair, non_null(:string))
      arg(:limit, non_null(:integer), default_value: 100)

      cache_resolve(&ExchangeResolver.last_exchange_trades/3)
    end

    @desc ~s"""
    Returns trades for given exchange and ticker pair between start and end datetime.
    Optionally the data can be aggregated and put into interval length buckets if `interval` arg is used.
    """
    field :exchange_trades, list_of(:exchange_trade) do
      meta(access: :free)

      arg(:exchange, non_null(:string))
      arg(:ticker_pair, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string)

      cache_resolve(&ExchangeResolver.exchange_trades/3)
    end

    @desc ~s"""
    Returns the mapping between exchange market pair and asset slugs.
    """
    field :exchange_market_pair_to_slugs, :slug_pair do
      meta(access: :free)

      arg(:exchange, non_null(:string))
      arg(:ticker_pair, non_null(:string))

      cache_resolve(&ExchangeResolver.exchange_market_pair_to_slugs/3,
        ttl: 3600,
        max_ttl_offset: 3600
      )
    end

    @desc ~s"""
    Returns the mapping between asset slugs and exchange market pair.
    """
    field :slugs_to_exchange_market_pair, :market_pair do
      meta(access: :free)

      arg(:exchange, non_null(:string))
      arg(:from_slug, non_null(:string))
      arg(:to_slug, non_null(:string))

      cache_resolve(&ExchangeResolver.slugs_to_exchange_market_pair/3,
        ttl: 3600,
        max_ttl_offset: 3600
      )
    end
  end
end
