defmodule SanbaseWeb.Graphql.Schema.TimelineQueries do
  @moduledoc ~s"""
  Queries and mutations for working user timelines
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.TimelineEventResolver
  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

  object :timeline_queries do
    field :timeline_events, list_of(:timeline_events_paginated) do
      meta(access: :free)

      arg(:cursor, :cursor_input)
      arg(:limit, :integer, default_value: 25)

      resolve(&TimelineEventResolver.timeline_events/3)
    end
  end

  object :timeline_mutations do
    @desc """
    Upvote a timeline event.
    """
    field :upvote_timeline_event, :timeline_event do
      arg(:timeline_event_id, :integer)
      middleware(JWTAuth)
      resolve(&TimelineEventResolver.upvote_timeline_event/3)
    end

    @desc """
    Downvote a timeline event.
    """
    field :downvote_timeline_event, :timeline_event do
      arg(:timeline_event_id, :integer)
      middleware(JWTAuth)
      resolve(&TimelineEventResolver.downvote_timeline_event/3)
    end
  end
end
