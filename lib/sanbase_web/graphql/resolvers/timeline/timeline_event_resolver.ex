defmodule SanbaseWeb.Graphql.Resolvers.TimelineEventResolver do
  require Logger

  import SanbaseWeb.Graphql.Helpers.Utils, only: [replace_user_trigger_with_trigger: 1]
  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.TimelineEvent.Like

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

  def like_timeline_event(_root, %{timeline_event_id: timeline_event_id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    case Like.like(%{user_id: current_user.id, timeline_event_id: timeline_event_id}) do
      {:ok, _} -> {:ok, TimelineEvent.by_id(timeline_event_id)}
      {:error, error} -> {:error, error}
    end
  end

  def unlike_timeline_event(_root, %{timeline_event_id: timeline_event_id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    case Like.unlike(%{user_id: current_user.id, timeline_event_id: timeline_event_id}) do
      {:ok, _} -> {:ok, TimelineEvent.by_id(timeline_event_id)}
      {:error, error} -> {:error, error}
    end
  end
end
