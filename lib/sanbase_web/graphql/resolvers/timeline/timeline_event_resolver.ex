defmodule SanbaseWeb.Graphql.Resolvers.TimelineEventResolver do
  require Logger

  alias Sanbase.Timeline.TimelineEvent

  def timeline_events(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    case TimelineEvent.events(current_user, args) do
      {:ok, events} ->
        {:ok, events}

      {:error, error} ->
        {:error, error}
    end
  end
end
