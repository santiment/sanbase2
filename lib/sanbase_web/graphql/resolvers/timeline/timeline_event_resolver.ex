defmodule SanbaseWeb.Graphql.Resolvers.TimelineEventResolver do
  require Logger

  alias Sanbase.Timeline.TimelineEvent

  def timeline_events(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    TimelineEvent.events(current_user, args)
  end
end
