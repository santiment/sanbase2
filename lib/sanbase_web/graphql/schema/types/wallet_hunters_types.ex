defmodule SanbaseWeb.Graphql.WalletHuntersTypes do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.{BlockchainAddressResolver, WalletHuntersResolver}

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

  input_object :wallet_hunters_request_object do
    field(:data, :string)
    field(:from, :binary_blockchain_address)
    field(:gas, :integer)
    field(:nonce, :string)
    field(:to, :binary_blockchain_address)
    field(:value, :integer)
  end

  input_object :wallet_hunters_proposals_selector_input_object do
    field(:filter, list_of(:wallet_hunters_filter_object))
    field(:sort_by, :wallet_hunters_sort_object)
    field(:page, :integer, default_value: 1)
    field(:page_size, :integer, default_value: 20)
    field(:type, :wallet_hunter_proposal_types, default_value: :all)
  end

  object :proposal_vote do
    field(:amount, :float)
    field(:voted_for, :boolean)
    field(:voter_address, :binary_blockchain_address)
  end

  object :wallet_hunters_vote do
    field(:proposal_id, :id)
    field(:user, :public_user)
    field(:transaction_id, :string)
    field(:transaction_status, :string)
  end

  object :wallet_hunters_bounty do
    field(:id, :integer)
    field(:user, :public_user)
    field(:title, :string)
    field(:description, :string)
    field(:duration, :interval)
    field(:proposal_reward, :integer)
    field(:proposals_count, :integer)
    field(:transaction_id, :string)
    field(:transaction_status, :string)
  end

  object :wallet_hunter_proposal do
    field(:id, :integer)
    field(:proposal_id, :id)
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
    field(:hunter_address, :binary_blockchain_address)
    field(:proposed_address, :binary_blockchain_address)
    field(:user_labels, list_of(:string))
    field(:votes, list_of(:proposal_vote))
    field(:votes_count, :integer)
    field(:transaction_id, :string)
    field(:transaction_status, :string)

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

    field :comments_count, :integer do
      resolve(&WalletHuntersResolver.comments_count/3)
    end
  end
end
