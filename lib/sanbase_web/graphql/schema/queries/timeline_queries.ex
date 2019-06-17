defmodule SanbaseWeb.Graphql.Schema.TimelineQueries do
  @moduledoc ~s"""
  Queries and mutations for working user timelines
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.TimelineEventResolver
  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

  object :timeline_queries do
    field :timeline_events, list_of(:timeline_events_paginated) do
      arg(:cursor, :cursor_input)
      arg(:limit, :integer, default_value: 25)

      middleware(JWTAuth)

      resolve(&TimelineEventResolver.timeline_events/3)
    end
  end
end
