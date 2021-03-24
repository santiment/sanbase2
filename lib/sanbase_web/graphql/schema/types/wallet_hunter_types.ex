defmodule SanbaseWeb.Graphql.WalletHunterTypes do
  use Absinthe.Schema.Notation

  enum :wallet_hunter_proposal_states do
    value(:active)
    value(:approved)
    value(:declined)
    value(:discarded)
  end

  object :wallet_hunter_proposal do
    field(:proposal_id, non_null(:id))
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
