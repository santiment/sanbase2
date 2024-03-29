defmodule SanbaseWeb.Graphql.Schema.VoteQueries do
  @moduledoc ~s"""
  Queries and mutations for working with Insights
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.VoteResolver
  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

  object :vote_mutations do
    @desc """
    Vote for an insight. The user must logged in.
    """
    field :vote, :vote_result do
      arg(:post_id, :integer, deprecate: "Use `insightId` instead")
      arg(:chart_configuration_id, :integer)
      arg(:dashboard_id, :integer)
      arg(:query_id, :integer)
      arg(:insight_id, :integer)
      arg(:timeline_event_id, :integer)
      arg(:user_trigger_id, :integer)
      arg(:watchlist_id, :integer)

      middleware(JWTAuth)
      resolve(&VoteResolver.vote/3)
    end

    @desc """
    Remove your vote for an insight. The user must logged in.
    """
    field :unvote, :vote_result do
      arg(:post_id, :integer, deprecate: "Use `insightId` instead")
      arg(:chart_configuration_id, :integer)
      arg(:dashboard_id, :integer)
      arg(:query_id, :integer)
      arg(:insight_id, :integer)
      arg(:timeline_event_id, :integer)
      arg(:user_trigger_id, :integer)
      arg(:watchlist_id, :integer)

      middleware(JWTAuth)
      resolve(&VoteResolver.unvote/3)
    end
  end
end
