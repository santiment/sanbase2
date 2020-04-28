defmodule Sanbase.Comments.Notification do
  import Ecto.Query

  alias Sanbase.Insight.PostComment
  alias Sanbase.Timeline.TimelineEventComment
  alias Sanbase.Repo

  def notify_users() do
    %{
      insight: notify_map(:insight),
      timeline_event: notify_map(:timeline_event)
    }
  end

  def notify_map(type) do
    recent_comments_query(type)
    |> Repo.all()
    |> Enum.reduce(%{}, fn comment, acc ->
      acc
      |> ntf_author(comment, type)
      |> ntf_reply(comment, type)
      |> ntf_previously_commented(comment, type)
    end)
  end

  # private functions

  defp ntf_author(
         notify_users_map,
         %PostComment{post: %{user: %{email: email}}} = comment,
         :insight
       )
       when is_binary(email) do
    put_event_in_map(notify_users_map, email, comment.id, "ntf_author")
  end

  defp ntf_author(
         notify_users_map,
         %TimelineEventComment{timeline_event: %{user: %{email: email}}} = comment,
         :timeline_event
       )
       when is_binary(email) do
    put_event_in_map(notify_users_map, email, comment.id, "ntf_author")
  end

  defp ntf_author(notify_users_map, _, _), do: notify_users_map

  defp ntf_reply(
         notify_users_map,
         %PostComment{comment: %{parent: %{user: %{email: email}}}} = comment,
         :insight
       )
       when is_binary(email) do
    put_event_in_map(notify_users_map, email, comment.id, "ntf_reply")
  end

  defp ntf_reply(
         notify_users_map,
         %TimelineEventComment{comment: %{parent: %{user: %{email: email}}}} = comment,
         :timeline_event
       )
       when is_binary(email) do
    put_event_in_map(notify_users_map, email, comment.id, "ntf_reply")
  end

  defp ntf_reply(notify_users_map, _, _), do: notify_users_map

  # Get comments on the same post added before certain comment
  defp ntf_previously_commented(notify_users_map, comment, type) do
    emails =
      previous_comments_query(comment, type)
      |> Repo.all()
      |> Enum.reject(&(&1.comment.id == comment.comment.parent_id))
      |> Enum.map(& &1.comment.user.email)
      |> Enum.reject(&(&1 == nil || &1 == comment.comment.user.email))

    put_event_in_map(
      notify_users_map,
      emails,
      comment.id,
      "ntf_previously_commented"
    )
  end

  defp put_event_in_map(notify_users_map, emails, comment_id, event) when is_list(emails) do
    Enum.reduce(emails, notify_users_map, fn email, acc ->
      put_event_in_map(acc, email, comment_id, event)
    end)
  end

  defp put_event_in_map(notify_users_map, email, comment_id, event) do
    events = notify_users_map[email][comment_id][:events] || []
    comment_map = %{comment_id => events ++ [event]}

    Map.update(notify_users_map, email, comment_map, fn current_map ->
      Map.merge(current_map, comment_map)
    end)
  end

  defp recent_comments_query(:insight) do
    yesterday = Timex.shift(Timex.now(), days: -1)

    from(p in PostComment,
      where: p.inserted_at > ^yesterday,
      preload: [comment: [:user, parent: :user], post: :user],
      order_by: [asc: :inserted_at]
    )
  end

  defp recent_comments_query(:timeline_event) do
    yesterday = Timex.shift(Timex.now(), days: -1)

    from(t in TimelineEventComment,
      where: t.inserted_at > ^yesterday,
      preload: [comment: [:user, parent: :user], timeline_event: :user],
      order_by: [asc: :inserted_at]
    )
  end

  defp previous_comments_query(post_comment, :insight) do
    from(p in PostComment,
      where:
        p.post_id == ^post_comment.post.id and p.comment_id != ^post_comment.comment.id and
          p.inserted_at < ^post_comment.inserted_at,
      preload: [comment: :user]
    )
  end

  defp previous_comments_query(timeline_event_comment, :timeline_event) do
    from(t in TimelineEventComment,
      where:
        t.timeline_event_id == ^timeline_event_comment.timeline_event.id and
          t.comment_id != ^timeline_event_comment.comment.id and
          t.inserted_at < ^timeline_event_comment.inserted_at,
      preload: [comment: :user]
    )
  end

  defp last_processed_id(result_map) do
    result_map
    |> Map.values()
    |> Enum.map(&Map.keys/1)
    |> List.flatten()
    |> Enum.max()
  end
end
