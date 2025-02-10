defmodule SanbaseWeb.Graphql.Schema.BlockchainQueries do
  @moduledoc false
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.BlockchainResolver

  object :blockchain_queries do
    field :get_available_blockchains, list_of(:blockchain_metadata) do
      meta(access: :free)
      resolve(&BlockchainResolver.available_blockchains_metadata/3)
    end
  end
end
