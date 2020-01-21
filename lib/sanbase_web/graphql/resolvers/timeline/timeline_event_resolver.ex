defmodule SanbaseWeb.Graphql.Resolvers.TimelineEventResolver do
  require Logger

  import Absinthe.Resolution.Helpers, except: [async: 1]

  import SanbaseWeb.Graphql.Helpers.Utils,
    only: [replace_user_trigger_with_trigger: 1]

  alias Sanbase.Timeline.{TimelineEvent, TimelineEventComment}
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

  def create_comment(
        _root,
        %{timeline_event_id: timeline_event_id, content: content} = args,
        %{context: %{auth: %{current_user: user}}}
      ) do
    TimelineEventComment.create_and_link(
      timeline_event_id,
      user.id,
      Map.get(args, :parent_id),
      content
    )
  end

  @spec update_comment(any, %{comment_id: any, content: any}, %{
          context: %{auth: %{current_user: atom | map}}
        }) :: any
  def update_comment(
        _root,
        %{comment_id: comment_id, content: content},
        %{context: %{auth: %{current_user: user}}}
      ) do
    TimelineEventComment.update_comment(comment_id, user.id, content)
  end

  def delete_comment(
        _root,
        %{comment_id: comment_id},
        %{context: %{auth: %{current_user: user}}}
      ) do
    TimelineEventComment.delete_comment(comment_id, user.id)
  end

  def insight_comments(
        _root,
        %{timeline_event_id: timeline_event_id} = args,
        _resolution
      ) do
    comments =
      TimelineEventComment.get_comments(timeline_event_id, args)
      |> Enum.map(& &1.comment)

    {:ok, comments}
  end

  def subcomments(
        _root,
        %{comment_id: comment_id} = args,
        _resolution
      ) do
    {:ok, TimelineEventComment.get_subcomments(comment_id, args)}
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
    |> Dataloader.load(SanbaseDataloader, :comments_count, id)
    |> on_load(fn loader ->
      {:ok, Dataloader.get(loader, SanbaseDataloader, :comments_count, id) || 0}
    end)
  end
end
