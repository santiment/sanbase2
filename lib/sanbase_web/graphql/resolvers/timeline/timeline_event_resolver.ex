defmodule SanbaseWeb.Graphql.Resolvers.TimelineEventResolver do
  require Logger

  import SanbaseWeb.Graphql.Helpers.Utils, only: [replace_user_trigger_with_trigger: 1]
  alias Sanbase.Timeline.TimelineEvent

  def timeline_events(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    case TimelineEvent.events(current_user, args) do
      {:ok, %{events: events} = result} ->
        {:ok, %{result | events: replace_user_trigger_with_trigger(events)}}

      {:error, error} ->
        {:error, error}
    end
  end
end
