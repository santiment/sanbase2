defmodule SanbaseWeb.Graphql.InsightCommentApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    clean_task_supervisor_children()

    user = insert(:user)
    post = insert(:post)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, user: user, post: post}
  end

  test "commentsCount on insights", context do
    %{conn: conn, post: post} = context
    assert comments_count(conn, post.id) == 0

    create_comment(conn, post.id, nil, "some content")
    assert comments_count(conn, post.id) == 1

    create_comment(conn, post.id, nil, "some content")
    create_comment(conn, post.id, nil, "some content")
    create_comment(conn, post.id, nil, "some content")
    assert comments_count(conn, post.id) == 4

    create_comment(conn, post.id, nil, "some content")
    assert comments_count(conn, post.id) == 5
  end

  test "comment an insight", context do
    %{conn: conn, post: post} = context

    content = "nice post"
    comment = create_comment(conn, post.id, nil, content)

    comments = insight_comments(conn, post.id)

    assert comment["insightId"] |> Sanbase.Math.to_integer() == post.id
    assert comment["content"] == content
    assert comment["insertedAt"] != nil
    assert comment["editedAt"] == nil
    assert length(comments) == 1
    assert comments |> List.first() |> Map.get("id") == comment["id"]
  end

  test "update a comment", context do
    %{conn: conn, post: post} = context

    content = "nice post"
    new_content = "updated content"

    comment = create_comment(conn, post.id, nil, content)
    updated_comment = update_comment(conn, comment["id"], new_content)
    comments = insight_comments(conn, post.id)

    assert comment["editedAt"] == nil
    assert updated_comment["editedAt"] != nil

    assert Sanbase.TestUtils.datetime_close_to(
             updated_comment["editedAt"]
             |> NaiveDateTime.from_iso8601!(),
             Timex.now(),
             1,
             :seconds
           ) == true

    assert comment["content"] == content
    assert updated_comment["content"] == new_content
    assert length(comments) == 1
    assert comments |> List.first() |> Map.get("content") == new_content
  end

  test "delete a comment", context do
    %{conn: conn, post: post} = context
    fallback_user = insert(:insights_fallback_user)

    content = "nice post"
    comment = create_comment(conn, post.id, nil, content)
    delete_comment(conn, comment["id"])

    comments = insight_comments(conn, post.id)
    post_comment = comments |> List.first()

    assert post_comment["user"]["id"] != comment["user"]["id"]
    assert post_comment["user"]["id"] |> Sanbase.Math.to_integer() == fallback_user.id

    assert post_comment["content"] != comment["content"]
    assert post_comment["content"] =~ "deleted"
  end

  test "create a subcomment", context do
    %{conn: conn, post: post} = context
    c1 = create_comment(conn, post.id, nil, "some content")
    c2 = create_comment(conn, post.id, c1["id"], "other content")
    create_comment(conn, post.id, c2["id"], "other content2")

    [comment, subcomment1, subcomment2] =
      insight_comments(conn, post.id)
      |> Enum.sort_by(&(&1["id"] |> String.to_integer()))

    assert comment["parentId"] == nil
    assert comment["rootParentId"] == nil

    assert subcomment1["parentId"] == comment["id"]
    assert subcomment1["rootParentId"] == comment["id"]

    assert subcomment2["parentId"] == subcomment1["id"]
    assert subcomment2["rootParentId"] == comment["id"]
  end

  defp create_comment(conn, post_id, parent_id, content) do
    mutation = """
    mutation {
      createComment(
        id: #{post_id}
        parentId: #{parent_id || "null"}
        content: "#{content}") {
          id
          content
          insightId
          user{ id username email }
          subcommentsCount
          insertedAt
          editedAt
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
    |> get_in(["data", "createComment"])
  end

  defp update_comment(conn, comment_id, content) do
    mutation = """
    mutation {
      updateComment(
        commentId: #{comment_id}
        content: "#{content}") {
          id
          content
          insightId
          user{ id username email }
          subcommentsCount
          insertedAt
          editedAt
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
    |> get_in(["data", "updateComment"])
  end

  defp delete_comment(conn, comment_id) do
    mutation = """
    mutation {
      deleteComment(commentId: #{comment_id}) {
        id
        content
        insightId
        user{ id username email }
        subcommentsCount
        insertedAt
        editedAt
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
    |> get_in(["data", "deleteComment"])
  end

  defp insight_comments(conn, post_id) do
    query = """
    {
      comments(
        id: #{post_id},
        cursor: {type: BEFORE, datetime: "#{Timex.now()}"}) {
          id
          content
          insightId
          parentId
          rootParentId
          user{ id username email }
          subcommentsCount
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "comments"])
  end

  defp comments_count(conn, post_id) do
    query = """
    {
      insight(id: #{post_id}) {
        commentsCount
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "insight", "commentsCount"])
  end
end
