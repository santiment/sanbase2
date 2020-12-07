defmodule SanbaseWeb.Graphql.Schema.BlockchainAddressQueries do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.BlockchainAddressResolver

  object :blockchain_address_queries do
    field :blockchain_address, :blockchain_address do
      arg(:selector, non_null(:blockchain_address_selector_input_object))

      resolve(&BlockchainAddressResolver.blockchain_address/3)
    end
  end
end
