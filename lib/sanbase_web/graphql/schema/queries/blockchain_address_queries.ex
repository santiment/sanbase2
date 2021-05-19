defmodule SanbaseWeb.Graphql.Schema.BlockchainAddressQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.BlockchainAddressResolver
  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

  object :blockchain_address_queries do
    field :blockchain_address_labels, list_of(:string) do
      meta(access: :free)

      arg(:blockchain, :string)

      cache_resolve(&BlockchainAddressResolver.list_all_labels/3)
    end

    @desc "Recent transactions for this address"
    field :recent_transactions, list_of(:transaction) do
      meta(access: :free)

      arg(:address, non_null(:string))
      arg(:type, non_null(:recent_transactions_type))
      arg(:page, non_null(:integer), default_value: 1)
      arg(:page_size, non_null(:integer), default_value: 10)
      arg(:only_sender, non_null(:boolean), default_value: true)

      cache_resolve(&BlockchainAddressResolver.recent_transactions/3)
    end

    field :blockchain_address, :blockchain_address do
      meta(access: :free)
      arg(:selector, non_null(:blockchain_address_selector_input_object))

      resolve(&BlockchainAddressResolver.blockchain_address/3)
    end

    field :blockchain_address_user_pair, :blockchain_address_user_pair do
      meta(access: :free)
      arg(:selector, non_null(:blockchain_address_selector_input_object))

      middleware(JWTAuth)
      resolve(&BlockchainAddressResolver.blockchain_address_user_pair/3)
    end
  end

  object :blockchain_address_mutations do
    field :update_blockchain_address_user_pair, :blockchain_address_user_pair do
      arg(:selector, non_null(:blockchain_address_selector_input_object))
      arg(:notes, :string)
      arg(:labels, list_of(:string))

      middleware(JWTAuth)
      resolve(&BlockchainAddressResolver.update_blockchain_address_user_pair/3)
    end
  end
end
