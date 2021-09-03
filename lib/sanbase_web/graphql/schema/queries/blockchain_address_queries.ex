defmodule SanbaseWeb.Graphql.Schema.BlockchainAddressQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.BlockchainAddressResolver
  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

  object :blockchain_address_queries do
    field :blockchain_address_label_changes, list_of(:blockchain_address_label_change) do
      meta(access: :free)

      arg(:selector, non_null(:blockchain_address_selector_input_object))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      cache_resolve(&BlockchainAddressResolver.blockchain_address_label_changes/3)
    end

    field :blockchain_address_labels, list_of(:string) do
      meta(access: :free)

      arg(:blockchain, :string)

      cache_resolve(&BlockchainAddressResolver.blockchain_address_labels/3)
    end

    field :get_blockchain_address_labels, list_of(:blockchain_address_label) do
      meta(access: :free)

      cache_resolve(&BlockchainAddressResolver.get_blockchain_address_labels/3)
    end

    @desc """
    Top transactions for the given slug and timerange arguments.
    """
    field :top_transfers, list_of(:account_based_transfer) do
      meta(access: :free)

      arg(:address_selector, :address_selector)
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:page, :integer)
      arg(:page_size, :integer)

      cache_resolve(&BlockchainAddressResolver.top_transfers/3)
    end

    @desc "Recent transactions for this address"
    field :recent_transactions, list_of(:transaction) do
      meta(access: :free)

      arg(:address, non_null(:string))
      arg(:type, non_null(:recent_transactions_type))
      arg(:page, :integer)
      arg(:page_size, :integer)
      arg(:only_sender, non_null(:boolean), default_value: true)

      cache_resolve(&BlockchainAddressResolver.recent_transactions/3)
    end

    field :blockchain_address, :blockchain_address_db_stored do
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
