defmodule SanbaseWeb.Graphql.Schema.NftQueries do
  @moduledoc ~s"""
  Queries and mutations for working with Insights
  """
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.NftResolver

  object :nft_queries do
    field :get_nft_trades, list_of(:nft_trade) do
      meta(access: :free)
      arg(:label_key, non_null(:nft_trade_label_key))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:page, non_null(:integer))
      arg(:page_size, non_null(:integer))
      arg(:order_by, non_null(:nft_trades_order_by))

      cache_resolve(&NftResolver.get_nft_trades/3, ttl: 30, max_ttl_offset: 30)
    end
  end

  object :nft_mutations do
  end
end
