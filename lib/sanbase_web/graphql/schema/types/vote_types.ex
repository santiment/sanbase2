defmodule SanbaseWeb.Graphql.VoteTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.VoteResolver

  object :vote_result do
    field(:voted_at, :datetime)

    field :votes, :vote do
      resolve(&VoteResolver.votes/3)
    end
  end

  object :vote do
    field(:total_votes, non_null(:integer))
    field(:total_voters, non_null(:integer))
    field(:current_user_votes, :integer)
  end
end
