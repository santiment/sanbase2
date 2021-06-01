defmodule SanbaseWeb.Graphql.Schema.WalletHunterQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.WalletHuntersResolver
  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

  object :wallet_hunter_queries do
    field :wallet_hunters_proposals, list_of(:wallet_hunter_proposal) do
      meta(access: :free)

      arg(:selector, :wallet_hunters_proposals_selector_input_object)

      cache_resolve(&WalletHuntersResolver.wallet_hunters_proposals/3, ttl: 60, max_ttl_offset: 30)
    end

    field :wallet_hunters_proposal, :wallet_hunter_proposal do
      meta(access: :free)

      arg(:id, :integer)
      arg(:proposal_id, :integer)

      cache_resolve(&WalletHuntersResolver.wallet_hunters_proposal/3, ttl: 60, max_ttl_offset: 30)
    end
  end

  object :wallet_hunter_mutations do
    field :create_wh_proposal, :wallet_hunter_proposal do
      meta(access: :free)

      arg(:transaction_id, :string)
      arg(:request, :wallet_hunters_request_object)
      arg(:signature, :string)

      arg(:title, non_null(:string))
      arg(:text, non_null(:string))
      arg(:proposed_address, non_null(:binary_blockchain_address))
      arg(:hunter_address, non_null(:binary_blockchain_address))
      arg(:user_labels, list_of(:string), default_value: [])

      middleware(JWTAuth)
      resolve(&WalletHuntersResolver.create_wh_proposal/3)
    end

    field :wallet_hunters_vote, :wallet_hunters_vote do
      meta(access: :free)

      arg(:transaction_id, :string)
      arg(:request, :wallet_hunters_request_object)
      arg(:signature, :string)

      arg(:proposal_id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&WalletHuntersResolver.wallet_hunters_vote/3)
    end
  end
end
