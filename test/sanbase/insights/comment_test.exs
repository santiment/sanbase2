defmodule Sanbase.Insight.CommentTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  alias Sanbase.Comments.{EntityComment, Notification}
  alias Sanbase.Comment

  @entity_type :insight

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

    assert Notification.notify_users() == %{
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

  test "add a comment to a post" do
    post = insert(:post)
    user = insert(:user)

    {:ok, comment} =
      EntityComment.create_and_link(@entity_type, post.id, user.id, nil, "some comment")

    post_comments = EntityComment.get_comments(@entity_type, post.id, %{cursor: nil, limit: 100})
    assert length(post_comments) == 1
    [%{comment: %{id: post_comment_id}}] = post_comments
    assert comment.id == post_comment_id
  end

  test "add a sub comment" do
    post = insert(:post)
    user = insert(:user)

    {:ok, comment1} =
      EntityComment.create_and_link(@entity_type, post.id, user.id, nil, "some comment")

    {:ok, comment2} =
      EntityComment.create_and_link(@entity_type, post.id, user.id, comment1.id, "some comment")

    assert comment2.parent_id == comment1.id
    assert comment2.root_parent_id == comment1.id
  end

  test "update a comment" do
    post = insert(:post)

    content = "some comment"
    updated_content = "updated content"

    {:ok, comment} =
      EntityComment.create_and_link(@entity_type, post.id, post.user_id, nil, content)

    naive_dt_before_update = NaiveDateTime.utc_now()

    {:ok, updated_comment} = Comment.update(comment.id, comment.user_id, updated_content)

    naive_dt_after_update = NaiveDateTime.utc_now()

    assert comment.edited_at == nil
    assert comment.content == content

    assert updated_comment.edited_at != nil
    assert NaiveDateTime.compare(updated_comment.edited_at, naive_dt_before_update) == :gt
    assert NaiveDateTime.compare(naive_dt_after_update, updated_comment.edited_at) == :gt
    assert updated_comment.content == updated_content
  end

  test "delete a comment" do
    post = insert(:post)
    fallback_user = insert(:insights_fallback_user)

    {:ok, comment} =
      EntityComment.create_and_link(@entity_type, post.id, post.user_id, nil, "some comment")

    {:ok, deleted} = Comment.delete(comment.id, comment.user_id)

    # The `delete` actually anonymizes instead of deleting. This is done so the
    # tree structure and links can be kept
    assert deleted.user_id == fallback_user.id
    assert deleted.content != comment.content
    assert deleted.content =~ "deleted"
  end

  test "root_parent_id is properly inherited" do
    post = insert(:post)
    user = insert(:user)

    {:ok, comment1} =
      EntityComment.create_and_link(@entity_type, post.id, user.id, nil, "some comment")

    {:ok, comment2} =
      EntityComment.create_and_link(@entity_type, post.id, user.id, comment1.id, "some comment")

    {:ok, comment3} =
      EntityComment.create_and_link(@entity_type, post.id, user.id, comment2.id, "some comment")

    {:ok, comment4} =
      EntityComment.create_and_link(@entity_type, post.id, user.id, comment3.id, "some comment")

    assert comment2.parent_id == comment1.id
    assert comment2.root_parent_id == comment1.id

    assert comment3.parent_id == comment2.id
    assert comment3.root_parent_id == comment1.id

    assert comment4.parent_id == comment3.id
    assert comment4.root_parent_id == comment1.id
  end

  defp entity_id(comment_id) do
    (Sanbase.Repo.get_by(Sanbase.Insight.PostComment, comment_id: comment_id) ||
       Sanbase.Repo.get_by(Sanbase.Timeline.TimelineEventComment, comment_id: comment_id)).id
  end
end
