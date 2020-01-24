defmodule SanbaseWeb.Graphql.Resolvers.TimelineEventResolver do
  require Logger

  import Absinthe.Resolution.Helpers, except: [async: 1]

  import SanbaseWeb.Graphql.Helpers.Utils,
    only: [replace_user_trigger_with_trigger: 1]

  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.Vote
  alias SanbaseWeb.Graphql.SanbaseDataloader

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

  def timeline_event(_root, %{id: timeline_event_id}, _resolution) do
    TimelineEvent.by_id(timeline_event_id)
    |> case do
      nil -> {:error, "There is no event with id #{timeline_event_id}"}
      timeline_event -> {:ok, timeline_event}
    end
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

  def timeline_event_id(%{id: id}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :comment_timeline_event_id, id)
    |> on_load(fn loader ->
      {:ok, Dataloader.get(loader, SanbaseDataloader, :comment_timeline_event_id, id)}
    end)
  end

  def comments_count(%TimelineEvent{id: id}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :timeline_events_comments_count, id)
    |> on_load(fn loader ->
      {:ok, Dataloader.get(loader, SanbaseDataloader, :timeline_events_comments_count, id) || 0}
    end)
  end
end
