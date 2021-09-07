defmodule Sanbase.Comments.NotificationTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  alias Sanbase.Comments.{EntityComment, Notification}

  setup do
    author = insert(:user)
    post = insert(:post, user: author)
    user = insert(:user)

    timeline_event =
      insert(:timeline_event,
        post: post,
        user: author,
        event_type: Sanbase.Timeline.TimelineEvent.publish_insight_type()
      )

    {:ok, user: user, author: author, post: post, timeline_event: timeline_event}
  end

  test "comments notification map", context do
    [user2, user3, user4] = [insert(:user), insert(:user), insert(:user)]

    {:ok, comment1} =
      EntityComment.create_and_link(:insight, context.post.id, context.user.id, nil, "comment1")

    EntityComment.create_and_link(:insight, context.post.id, user2.id, nil, "comment2")

    {:ok, comment3} =
      EntityComment.create_and_link(
        :insight,
        context.post.id,
        user3.id,
        comment1.id,
        "subcomment"
      )

    {:ok, comment4} =
      EntityComment.create_and_link(
        :timeline_event,
        context.timeline_event.id,
        user4.id,
        nil,
        "an event comment"
      )

    comment_notification = Notification.build_ntf_events_map()

    assert comment_notification.last_insight_comment_id == entity_id(comment3.id)
    assert comment_notification.last_timeline_event_comment_id == entity_id(comment4.id)

    author_data = comment_notification.notify_users_map[context.author.email]
    assert length(author_data) == 4

    author_events =
      Enum.map(author_data, fn %{event: event} -> event end)
      |> Enum.filter(&(&1 == "ntf_author"))

    assert length(author_events) == 4

    assert Enum.map(comment_notification.notify_users_map[context.user.email], fn %{event: event} ->
             event
           end) == ["ntf_previously_commented", "ntf_reply"]
  end

  defp entity_id(comment_id) do
    (Sanbase.Repo.get_by(Sanbase.Comment.PostComment, comment_id: comment_id) ||
       Sanbase.Repo.get_by(Sanbase.Comment.TimelineEventComment, comment_id: comment_id)).id
  end
end
