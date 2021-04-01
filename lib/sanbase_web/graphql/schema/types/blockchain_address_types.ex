defmodule SanbaseWeb.Graphql.BlockchainAddressType do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.BlockchainAddressResolver

  enum :recent_transactions_type do
    value(:eth)
    value(:erc20)
  end

  object :current_user_blockchain_address_data do
    field(:pair_id, :integer)
    field(:notes, :string)
    field(:labels, list_of(:blockchain_address_label))
  end

  object :blockchain_address_user_pair do
    field(:id, :integer)
    field(:notes, :string)
    field(:labels, list_of(:blockchain_address_label))
    field(:blockchain_address, :blockchain_address)
    field(:user, :user)
  end

  input_object :blockchain_address_selector_input_object do
    field(:id, :id)
    field(:address, :binary_blockchain_address)
    field(:infrastructure, :string)
  end

  object :blockchain_address_label do
    field(:name, :string)
    field(:notes, :string)
    field(:origin, :string, default_value: "user")
    field(:metadata, :json, default_value: %{})
  end

  object :blockchain_address do
    field(:id, :integer)
    field(:address, :binary_blockchain_address)

    field :infrastructure, :string do
      cache_resolve(&BlockchainAddressResolver.infrastructure/3)
    end

    field :labels, list_of(:blockchain_address_label) do
      cache_resolve(&BlockchainAddressResolver.labels/3)
    end

    field(:notes, :string)

    field :balance, :float do
      arg(:selector, non_null(:historical_balance_selector))
      cache_resolve(&BlockchainAddressResolver.balance/3)
    end

    @desc ~s"""
    Shows what percentage of the total balance of the whole watchlist of a specific
    coin/token a given address holds. If there are no other addresses in the watchlist
    or the field is not executed in the context of a watchlist, 1.0 is returned.
    """
    field :balance_dominance, :float do
      arg(:selector, non_null(:historical_balance_selector))
      cache_resolve(&BlockchainAddressResolver.balance_dominance/3)
    end

    field :balance_change, :address_balance_change do
      arg(:selector, non_null(:historical_balance_selector))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      cache_resolve(&BlockchainAddressResolver.balance_change/3)
    end

    field :comments_count, :integer do
      resolve(&BlockchainAddressResolver.comments_count/3)
    end
  end
end
