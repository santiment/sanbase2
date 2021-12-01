defmodule SanbaseWeb.Graphql.VoteTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.VoteResolver

  enum :vote_entity do
    value(:insight)
    value(:watchlist)
    value(:screener)
    value(:timeline_event)
    value(:chart_configuration)
  end

  object :most_voted_result do
    field(:insight, :post)
    field(:watchlist, :user_list)
    field(:screener, :user_list)
    field(:timeline_event, :timeline_event)
    field(:chart_configuration, :chart_configuration)
  end

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
