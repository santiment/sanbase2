defmodule SanbaseWeb.Graphql.Schema.BlockchainAddressQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.BlockchainAddressResolver

  object :blockchain_address_queries do
    @desc "Recent transactions for this address"
    field :recent_transactions, list_of(:transaction) do
      arg(:address, non_null(:string))
      arg(:type, non_null(:recent_transactions_type))
      arg(:page, non_null(:integer), default_value: 1)
      arg(:page_size, non_null(:integer), default_value: 10)
      arg(:only_sender, non_null(:boolean), default_value: true)

      cache_resolve(&BlockchainAddressResolver.recent_transactions/3)
    end

    field :blockchain_address, :blockchain_address do
      arg(:selector, non_null(:blockchain_address_selector_input_object))

      resolve(&BlockchainAddressResolver.blockchain_address/3)
    end
  end
end
