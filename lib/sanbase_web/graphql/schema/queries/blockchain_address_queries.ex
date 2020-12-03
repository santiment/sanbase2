defmodule SanbaseWeb.Graphql.Schema.BlockchainAddressQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.BlockchainAddressResolver

  object :blockchain_address_queries do
    @desc "Recent ethereum transactions for address"
    field :eth_recent_transactions, list_of(:transaction) do
      arg(:address, non_null(:string))
      arg(:page, non_null(:integer), default_value: 1)
      arg(:page_size, non_null(:integer), default_value: 10)

      # TODO change to cache_resolve
      resolve(&BlockchainAddressResolver.eth_recent_transactions/3)
    end

    @desc "Recent erc20 transactions for address"
    field :token_recent_transactions, list_of(:transaction) do
      arg(:address, non_null(:string))
      arg(:page, non_null(:integer), default_value: 1)
      arg(:page_size, non_null(:integer), default_value: 10)

      # TODO change to cache_resolve
      resolve(&BlockchainAddressResolver.token_recent_transactions/3)
    end
  end
end
