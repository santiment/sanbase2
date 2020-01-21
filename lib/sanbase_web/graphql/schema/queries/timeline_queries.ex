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

    field :timeline_event_comments, list_of(:timeline_event_comment) do
      arg(:timeline_event_id, non_null(:id))
      arg(:cursor, :cursor_input, default_value: nil)
      arg(:limit, :integer, default_value: 50)

      resolve(&TimelineEventResolver.insight_comments/3)
    end

    field :subcomments, list_of(:timeline_event_comment) do
      arg(:comment_id, non_null(:id))
      arg(:limit, :integer, default_value: 100)

      resolve(&TimelineEventResolver.subcomments/3)
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

    field :create_timeline_event_comment, :timeline_event_comment do
      arg(:timeline_event_id, non_null(:integer))
      arg(:content, non_null(:string))
      arg(:parent_id, :integer)

      middleware(JWTAuth)

      resolve(&TimelineEventResolver.create_comment/3)
    end

    field :update_timeline_event_comment, :timeline_event_comment do
      arg(:comment_id, non_null(:integer))
      arg(:content, non_null(:string))

      middleware(JWTAuth)

      resolve(&TimelineEventResolver.update_comment/3)
    end

    field :delete_timeline_event_comment, :timeline_event_comment do
      arg(:comment_id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&TimelineEventResolver.delete_comment/3)
    end
  end
end
