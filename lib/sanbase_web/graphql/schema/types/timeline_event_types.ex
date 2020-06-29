defmodule SanbaseWeb.Graphql.TimelineEventTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.TimelineEventResolver

  enum :order_by_enum do
    value(:datetime)
    value(:votes)
    value(:comments)
    value(:author)
  end

  enum :tag_enum do
    value(:by_me)
    value(:by_sanfam)
    value(:by_followed)
    value(:insight)
    value(:pulse)
    value(:alert)
  end

  enum(:author_filter, values: [:all, :own, :followed, :sanfam])
  enum(:type_filter, values: [:insight, :pulse, :alert])

  input_object :timeline_events_filter_input do
    field(:author, :author_filter, default_value: :all)
    field(:type, :type_filter)
    field(:watchlists, list_of(:integer), default_value: nil)
    field(:assets, list_of(:integer), default_value: nil)
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
end
