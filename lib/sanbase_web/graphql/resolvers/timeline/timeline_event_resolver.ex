defmodule SanbaseWeb.Graphql.Resolvers.TimelineEventResolver do
  require Logger

  import SanbaseWeb.Graphql.Helpers.Utils,
    only: [replace_user_trigger_with_trigger: 1]

  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.Vote

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

  def timeline_events(_root, args, _resolution) do
    {:ok, %{events: events} = result} = TimelineEvent.events(args)
    {:ok, %{result | events: replace_user_trigger_with_trigger(events)}}
  end

  def upvote_timeline_event(_root, %{timeline_event_id: timeline_event_id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    case Vote.create(%{user_id: current_user.id, timeline_event_id: timeline_event_id}) do
      {:ok, _} ->
        {:ok, TimelineEvent.by_id(timeline_event_id)}

      {:error, _error} ->
        {:error, "Can't vote for event with id #{timeline_event_id}"}
    end
  end

  def downvote_timeline_event(_root, %{timeline_event_id: timeline_event_id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    with %Vote{} = vote <-
           Vote.get_by_opts(timeline_event_id: timeline_event_id, user_id: current_user.id),
         {:ok, _vote} <- Vote.remove(vote) do
      {:ok, TimelineEvent.by_id(timeline_event_id)}
    else
      _error ->
        {:error, "Can't remove vote for event with id #{timeline_event_id}"}
    end
  end
end
