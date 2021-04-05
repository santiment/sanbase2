defmodule SanbaseWeb.Graphql.WalletHuntersTypes do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.BlockchainAddressResolver

  enum :wallet_hunter_proposal_types do
    value(:all)
    value(:only_voted)
    value(:only_mine)
  end

  enum :wallet_hunter_proposal_states do
    value(:active)
    value(:approved)
    value(:declined)
    value(:discarded)
  end

  enum :sort_direction do
    value(:asc)
    value(:desc)
  end

  input_object :wallet_hunters_filter_object do
    field(:field, :string)
    field(:value, :string)
  end

  input_object :wallet_hunters_sort_object do
    field(:field, :string)
    field(:direction, :sort_direction)
  end

  input_object :wallet_hunters_proposals_selector_input_object do
    field(:filter, list_of(:wallet_hunters_filter_object))
    field(:sort_by, :wallet_hunters_sort_object)
    field(:page, :integer, default_value: 1)
    field(:page_size, :integer, default_value: 10)
    field(:type, :wallet_hunter_proposal_types, default_value: :all)
  end

  object :proposal_vote do
    field(:amount, :float)
    field(:voted_for, :boolean)
    field(:voter_address, :string)
  end

  object :wallet_hunter_proposal do
    field(:proposal_id, non_null(:id))
    field(:user, :public_user)
    field(:title, :string)
    field(:text, :string)
    field(:reward, :float)
    field(:state, :wallet_hunter_proposal_states)
    field(:is_reward_claimed, :boolean)
    field(:created_at, :datetime)
    field(:finish_at, :datetime)
    field(:votes_for, :float)
    field(:votes_against, :float)
    field(:sheriffs_reward_share, :float)
    field(:fixed_sheriff_reward, :float)
    field(:hunter_address, :string)
    field(:proposed_address, :string)
    field(:user_labels, list_of(:string))
    field(:votes, list_of(:proposal_vote))
    field(:votes_count, :integer)

    field :hunter_address_labels, list_of(:blockchain_address_label) do
      cache_resolve(
        &BlockchainAddressResolver.labels(%{address: Map.get(&1, :hunter_address)}, &2, &3),
        ttl: 600,
        max_ttl_offset: 600
      )
    end

    field :proposed_address_labels, list_of(:blockchain_address_label) do
      cache_resolve(
        &BlockchainAddressResolver.labels(%{address: Map.get(&1, :proposed_address)}, &2, &3),
        ttl: 600,
        max_ttl_offset: 600
      )
    end
  end
end
