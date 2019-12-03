defmodule Sanbase.Insight.CommentTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  alias Sanbase.Insight.{Comment, PostComment}

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

  test "root_parent_id is properly iherited" do
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
