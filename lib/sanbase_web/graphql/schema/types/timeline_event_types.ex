defmodule SanbaseWeb.Graphql.TimelineEventTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.TimelineEventResolver

  enum :order_by_enum do
    value(:datetime)
    value(:votes)
    value(:comments)
    value(:author)
  end

  enum :tag_enum do
    value(:own)
    value(:sanfam)
    value(:followed)
    value(:insight)
    value(:pulse)
    value(:alert)
  end

  enum(:author_filter, values: [:all, :own, :followed, :sanfam])
  enum(:type_filter, values: [:all, :insight, :pulse, :alert])

  input_object :timeline_events_filter_input do
    field(:author, :author_filter)
    field(:type, :type_filter)
    field(:watchlists, list_of(:integer))
    field(:assets, list_of(:integer))
    field(:only_not_seen, :boolean)
  end

  object :timeline_events_paginated do
    field(:events, list_of(:timeline_event))
    field(:cursor, :cursor)
  end

  object :timeline_event do
    field(:id, non_null(:integer))
    field(:event_type, non_null(:string))
    field(:inserted_at, non_null(:datetime))
    field(:user, non_null(:public_user))
    field(:trigger, :trigger)
    field(:post, :post)
    field(:user_list, :user_list)
    field(:payload, :json)
    field(:data, :json)
    field(:votes, list_of(:upvote))
    field(:tags, list_of(:tag_enum))

    field :comments_count, :integer do
      resolve(&TimelineEventResolver.comments_count/3)
    end
  end

  object :upvote do
    field(:user_id, :integer)
  end

  object :seen_event do
    field(:event_id, non_null(:integer))
    field(:seen_at, non_null(:datetime))
  end
end
