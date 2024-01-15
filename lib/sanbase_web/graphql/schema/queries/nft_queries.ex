defmodule SanbaseWeb.Graphql.Schema.NftQueries do
  @moduledoc ~s"""
  Queries and mutations for working with Insights
  """
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.NftResolver

  object :nft_queries do
    field :get_nft_trades, list_of(:nft_trade) do
      meta(access: :free)
      arg(:label_key, non_null(:nft_trade_label_key))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:page, non_null(:integer))
      arg(:page_size, non_null(:integer))
      arg(:order_by, :nft_trades_order_by, default_value: :datetime)
      arg(:direction, :sort_direction, default_value: :desc)

      cache_resolve(&NftResolver.get_nft_trades/3, ttl: 30, max_ttl_offset: 30)
    end

    field :get_nft_trades_count, :integer do
      meta(access: :free)
      arg(:label_key, non_null(:nft_trade_label_key))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      cache_resolve(&NftResolver.get_nft_trades_count/3,
        ttl: 30,
        max_ttl_offset: 30
      )
    end

    field :get_nft_collection_by_contract, :nft_contract_data do
      meta(access: :free)

      arg(:selector, non_null(:nft_contract_input_object))

      cache_resolve(&NftResolver.get_nft_collection_by_contract/3)
    end
  end
end
