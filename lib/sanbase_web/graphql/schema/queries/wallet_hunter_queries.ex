defmodule SanbaseWeb.Graphql.Schema.WalletHunterQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.WalletHuntersResolver

  object :wallet_hunter_queries do
    field :wallet_hunters_proposals, list_of(:wallet_hunter_proposal) do
      meta(access: :free)
      arg(:selector, :wallet_hunters_proposals_selector_input_object)

      cache_resolve(&WalletHuntersResolver.wallet_hunters_proposals/3)
    end
  end

  object :wallet_hunter_mutations do
    field :create_wallet_hunter_proposal, :wallet_hunter_proposal do
      meta(access: :free)

      arg(:proposal_id, non_null(:integer))
      arg(:title, non_null(:string))
      arg(:text, non_null(:string))
      arg(:hunter_address, non_null(:string))
      arg(:signature, non_null(:string))
      arg(:message_hash, non_null(:string))

      cache_resolve(&WalletHuntersResolver.create_wallet_hunter_proposal/3)
    end
  end
end
