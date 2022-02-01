defmodule SanbaseWeb.Graphql.Schema.BlockchainAddressQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Complexity
  alias SanbaseWeb.Graphql.Middlewares.JWTAuth
  alias SanbaseWeb.Graphql.Middlewares.AccessControl
  alias SanbaseWeb.Graphql.Resolvers.BlockchainAddressResolver

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
    Top transfers for the given slug and timerange arguments.
    """
    field :top_transfers, list_of(:account_based_transfer) do
      meta(access: :free)

      arg(:address_selector, :address_selector)
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:page, :integer)
      arg(:page_size, :integer)
      arg(:in_page_order_by, :in_page_order_by_type, default_value: :trx_value)
      arg(:in_page_order_by_direction, :direction_type, default_value: :desc)

      cache_resolve(&BlockchainAddressResolver.top_transfers/3)
    end

    @desc "Recent transfers for this address"
    field :recent_transfers, list_of(:transaction) do
      meta(access: :free)

      arg(:address, non_null(:string))
      arg(:type, non_null(:recent_transactions_type))
      arg(:page, :integer)
      arg(:page_size, :integer)
      arg(:only_sender, non_null(:boolean), default_value: true)

      cache_resolve(&BlockchainAddressResolver.recent_transactions/3)
    end

    @desc "Recent transfers for this address"
    field :recent_transactions, list_of(:transaction) do
      deprecate("Use recentTransfers instead.")
      meta(access: :free)

      arg(:address, non_null(:string))
      arg(:type, non_null(:recent_transactions_type))
      arg(:page, :integer)
      arg(:page_size, :integer)
      arg(:only_sender, non_null(:boolean), default_value: true)

      cache_resolve(&BlockchainAddressResolver.recent_transactions/3)
    end

    @desc "Recent transfers for this address"
    field :recent_transfers, list_of(:transaction) do
      deprecate("Use recentTransfers instead.")
      meta(access: :free)

      arg(:address, non_null(:string))
      arg(:type, non_null(:recent_transactions_type))
      arg(:page, :integer)
      arg(:page_size, :integer)
      arg(:only_sender, non_null(:boolean), default_value: true)

      cache_resolve(&BlockchainAddressResolver.recent_transactions/3)
    end

    @desc ~s"""
    Ret
    """
    field :incoming_transfers_summary, list_of(:transfers_summary) do
      meta(access: :free)

      arg(:slug, non_null(:string))
      arg(:address, non_null(:string))
      arg(:page, non_null(:integer))
      arg(:page_size, non_null(:integer))
      arg(:order_by, non_null(:transfers_summary_order_by))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      cache_resolve(&BlockchainAddressResolver.incoming_transfers_summary/3)
    end

    @desc ~s"""

    """
    field :outgoing_transfers_summary, list_of(:transfers_summary) do
      meta(access: :free)

      arg(:slug, non_null(:string))
      arg(:address, non_null(:string))
      arg(:page, non_null(:integer))
      arg(:page_size, non_null(:integer))
      arg(:order_by, non_null(:transfers_summary_order_by))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      cache_resolve(&BlockchainAddressResolver.outgoing_transfers_summary/3)
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

    field :transaction_volume_per_address, list_of(:address_transaction_volume) do
      meta(access: :free)

      arg(:selector, :historical_balance_selector)
      arg(:addresses, list_of(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&BlockchainAddressResolver.transaction_volume_per_address/3)
    end

    field :blockchain_address_transaction_volume_over_time,
          list_of(:combined_address_transaction_volume_over_time) do
      meta(access: :free)

      arg(:selector, :historical_balance_selector)
      arg(:addresses, list_of(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, non_null(:interval))

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&BlockchainAddressResolver.blockchain_address_transaction_volume_over_time/3)
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
