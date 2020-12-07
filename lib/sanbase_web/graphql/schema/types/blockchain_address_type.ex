defmodule SanbaseWeb.Graphql.BlockchainAddressType do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.BlockchainAddressResolver

  input_object :blockchain_address_selector_input_object do
    field(:id, :id)
    field(:address, :string)
    field(:infrastructure_code, :string)
  end

  object :blockchain_address_label do
    field(:name, :string)
    field(:notes, :string)
  end

  object :blockchain_address do
    field(:address, :string)
    field(:infrastructure, :infrastructure)
    field(:labels, list_of(:blockchain_address_label))
    field(:notes, :string)

    field :comments_count, :integer do
      resolve(&BlockchainAddressResolver.comments_count/3)
    end
  end
end
