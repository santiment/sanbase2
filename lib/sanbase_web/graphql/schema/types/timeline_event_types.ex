defmodule SanbaseWeb.Graphql.TimelineEventTypes do
  use Absinthe.Schema.Notation

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
    field(:likes, list_of(:like))
    field(:likes_count, non_null(:integer))
    field(:liked_by_current_user, non_null(:boolean))
  end

  object :like do
    field(:user_id, :integer)
  end
end
