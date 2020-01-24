defmodule Sanbase.Insight.CommentTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  alias Sanbase.Insight.PostComment

  test "add a comment to a post" do
    post = insert(:post)
    user = insert(:user)
    {:ok, comment} = PostComment.create_and_link(post.id, user.id, nil, "some comment")

    post_comments = PostComment.get_comments(post.id, %{cursor: nil, limit: 100})
    assert length(post_comments) == 1
    [%{comment: %{id: post_comment_id}}] = post_comments
    assert comment.id == post_comment_id
  end

  test "add a sub comment" do
    post = insert(:post)
    user = insert(:user)
    {:ok, comment1} = PostComment.create_and_link(post.id, user.id, nil, "some comment")

    {:ok, comment2} = PostComment.create_and_link(post.id, user.id, comment1.id, "some comment")

    assert comment2.parent_id == comment1.id
    assert comment2.root_parent_id == comment1.id
  end

  test "update a comment" do
    post = insert(:post)

    content = "some comment"
    updated_content = "updated content"

    {:ok, comment} = PostComment.create_and_link(post.id, post.user_id, nil, content)

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

    {:ok, comment} = PostComment.create_and_link(post.id, post.user_id, nil, "some comment")

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
    {:ok, comment1} = PostComment.create_and_link(post.id, user.id, nil, "some comment")
    {:ok, comment2} = PostComment.create_and_link(post.id, user.id, comment1.id, "some comment")
    {:ok, comment3} = PostComment.create_and_link(post.id, user.id, comment2.id, "some comment")
    {:ok, comment4} = PostComment.create_and_link(post.id, user.id, comment3.id, "some comment")

    assert comment2.parent_id == comment1.id
    assert comment2.root_parent_id == comment1.id

    assert comment3.parent_id == comment2.id
    assert comment3.root_parent_id == comment1.id

    assert comment4.parent_id == comment3.id
    assert comment4.root_parent_id == comment1.id
  end
end
