defmodule SanbaseWeb.Graphql.Schema.VoteQueries do
  @moduledoc ~s"""
  Queries and mutations for working with Insights
  """
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.VoteResolver
  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

  object :vote_queries do
    field :get_most_voted, list_of(:most_voted_result) do
      meta(access: :free)
      arg(:type, :vote_entity)
      arg(:page, :integer)
      arg(:page_size, :integer)

      cache_resolve(&VoteResolver.get_most_voted/3, ttl: 30, max_ttl_offset: 30)
    end
  end

  object :vote_mutations do
    @desc """
    Vote for an insight. The user must logged in.
    """
    field :vote, :vote_result do
      arg(:post_id, :integer, deprecate: "Use `insightId` instead")
      arg(:insight_id, :integer)
      arg(:watchlist_id, :integer)
      arg(:timeline_event_id, :integer)
      arg(:chart_configuration_id, :integer)

      middleware(JWTAuth)
      resolve(&VoteResolver.vote/3)
    end

    @desc """
    Remove your vote for an insight. The user must logged in.
    """
    field :unvote, :vote_result do
      arg(:post_id, :integer, deprecate: "Use `insightId` instead")
      arg(:insight_id, :integer)
      arg(:watchlist_id, :integer)
      arg(:timeline_event_id, :integer)
      arg(:chart_configuration_id, :integer)

      middleware(JWTAuth)
      resolve(&VoteResolver.unvote/3)
    end
  end
end
