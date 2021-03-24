defmodule SanbaseWeb.Graphql.WalletHunterTypes do
  use Absinthe.Schema.Notation

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
  end

  object :wallet_hunter_proposal do
    field(:proposal_id, non_null(:id))
    field(:user, :public_user)
    field(:title, :string)
    field(:text, :string)
    field(:hunter_address, :string)
    field(:reward, :float)
    field(:state, :wallet_hunter_proposal_states)
    field(:claimed_reward, :boolean)
    field(:created_at, :datetime)
    field(:finish_at, :datetime)
    field(:votes_for, :float)
    field(:votes_against, :float)
    field(:sheriffs_reward_share, :float)
    field(:fixed_sheriff_reward, :float)
  end
end
