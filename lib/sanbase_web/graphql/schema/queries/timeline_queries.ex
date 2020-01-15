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

      middleware(JWTAuth)
      resolve(&TimelineEventResolver.timeline_events/3)
    end
  end

  object :timeline_mutations do
    @desc """
    Like a timeline event.
    """
    field :like_timeline_event, :timeline_event do
      arg(:timeline_event_id, :integer)
      middleware(JWTAuth)
      resolve(&TimelineEventResolver.like_timeline_event/3)
    end

    @desc """
    Unlike a timeline event.
    """
    field :unlike_timeline_event, :timeline_event do
      arg(:timeline_event_id, :integer)
      middleware(JWTAuth)
      resolve(&TimelineEventResolver.unlike_timeline_event/3)
    end
  end
end
