defmodule SanbaseWeb.Graphql.BlockchainAddressType do
  use Absinthe.Schema.Notation

  object :blockchain_address_label do
    field(:label, :string)
    field(:notes, :string)
  end

  object :blockchain_address do
    field(:address, :string)
    field(:infrastructure, :infrastructure)
    field(:labels, list_of(:blockchain_address_label))
    field(:notes, :string)
  end
end
