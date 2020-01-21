defmodule SanbaseWeb.Graphql.TimelineEventTypes do
  use Absinthe.Schema.Notation

  import Absinthe.Resolution.Helpers

  alias SanbaseWeb.Graphql.Resolvers.TimelineEventResolver
  alias SanbaseWeb.Graphql.SanbaseRepo

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
  end

  object :upvote do
    field(:user_id, :integer)
  end

  object :timeline_event_comment do
    field(:id, non_null(:id))

    field :timeline_event_id, non_null(:id) do
      resolve(&TimelineEventResolver.timeline_event_id/3)
    end

    field(:content, non_null(:string))
    field(:user, non_null(:public_user), resolve: dataloader(SanbaseRepo))
    field(:parent_id, :id)
    field(:root_parent_id, :id)
    field(:subcomments_count, :integer)
    field(:inserted_at, non_null(:datetime))
    field(:edited_at, :datetime)
  end
end
