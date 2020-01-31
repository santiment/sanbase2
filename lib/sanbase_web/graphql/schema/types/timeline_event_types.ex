defmodule SanbaseWeb.Graphql.TimelineEventTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.TimelineEventResolver

  enum :order_by_enum do
    value(:datetime)
    value(:votes)
    value(:comments)
    value(:author)
  end

  enum(:author_filter, values: [:all, :own, :followed, :sanfam])

  input_object :timeline_events_filter_input do
    field(:author, :author_filter)
    field(:watchlists, list_of(:integer))
    field(:assets, list_of(:string))
  end

  object :timeline_events_paginated do
    field(:events, list_of(:timeline_event))
    field(:cursor, :cursor)
  end

  object :timeline_event do
    field(:id, non_null(:id))
    field(:event_type, non_null(:string))
    field(:inserted_at, non_null(:datetime))
    field(:user, non_null(:user))
    field(:trigger, :trigger)
    field(:post, :post)
    field(:user_list, :user_list)
    field(:payload, :json)
    field(:votes, list_of(:upvote))

    field :comments_count, :integer do
      resolve(&TimelineEventResolver.comments_count/3)
    end
  end

  object :upvote do
    field(:user_id, :integer)
  end
end
