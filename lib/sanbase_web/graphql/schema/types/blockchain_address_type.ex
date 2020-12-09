defmodule SanbaseWeb.Graphql.BlockchainAddressType do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.BlockchainAddressResolver

  enum :recent_transactions_type do
    value(:eth)
    value(:erc20)
  end

  input_object :blockchain_address_selector_input_object do
    field(:id, :id)
    field(:address, :string)
    field(:infrastructure, :string)
  end

  object :blockchain_address_label do
    field(:name, :string)
    field(:notes, :string)
  end

  object :blockchain_address do
    field(:id, :integer)
    field(:address, :string)
    field(:infrastructure, :infrastructure)
    field(:labels, list_of(:blockchain_address_label))
    field(:notes, :string)

    field :balance, :float do
      arg(:selector, :historical_balance_selector)
      cache_resolve(&BlockchainAddressResolver.balance/3)
    end

    field :comments_count, :integer do
      resolve(&BlockchainAddressResolver.comments_count/3)
    end
  end
end
