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

    {:ok, comment2} =
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

    {:ok, comment_notification} = Notification.notify_users()

    assert comment_notification.last_insight_comment_id == entity_id(comment3.id)
    assert comment_notification.last_timeline_event_comment_id == entity_id(comment4.id)

    assert comment_notification.notify_users_map == %{
             insight: %{
               context.user.email => %{
                 entity_id(comment2.id) => ["ntf_previously_commented"],
                 entity_id(comment3.id) => ["ntf_reply"]
               },
               user2.email => %{
                 entity_id(comment3.id) => ["ntf_previously_commented"]
               },
               context.author.email => %{
                 entity_id(comment1.id) => ["ntf_author"],
                 entity_id(comment2.id) => ["ntf_author"],
                 entity_id(comment3.id) => ["ntf_author"]
               }
             },
             timeline_event: %{
               context.author.email => %{
                 entity_id(comment4.id) => ["ntf_author"]
               }
             }
           }
  end

  defp entity_id(comment_id) do
    (Sanbase.Repo.get_by(Sanbase.Insight.PostComment, comment_id: comment_id) ||
       Sanbase.Repo.get_by(Sanbase.Timeline.TimelineEventComment, comment_id: comment_id)).id
  end
end
