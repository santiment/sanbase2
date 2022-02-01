defmodule SanbaseWeb.Graphql.ShortUrlCommentApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    clean_task_supervisor_children()

    user = insert(:user)
    short_url = insert(:short_url)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, user: user, short_url: short_url}
  end

  test "comment a short url", context do
    %{short_url: short_url, conn: conn, user: user} = context
    other_user_conn = setup_jwt_auth(build_conn(), insert(:user))

    content = "nice short_url"

    comment = create_comment(conn, short_url.id, nil, content)

    comments = short_url_comments(other_user_conn, short_url.id)

    assert comment["shortUrlId"] |> Sanbase.Math.to_integer() == short_url.id
    assert comment["content"] == content
    assert comment["insertedAt"] != nil
    assert comment["editedAt"] == nil
    assert comment["user"]["email"] == user.email
    assert length(comments) == 1
    assert comments |> List.first() |> Map.get("id") == comment["id"]
    assert comments |> hd() |> get_in(["user", "email"]) == "<email hidden>"
  end

  test "update a comment", context do
    %{conn: conn, short_url: short_url} = context

    content = "nice short_url"
    new_content = "updated content"

    comment = create_comment(conn, short_url.id, nil, content)
    updated_comment = update_comment(conn, comment["id"], new_content)
    comments = short_url_comments(conn, short_url.id)

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
    %{conn: conn, short_url: short_url} = context
    fallback_user = insert(:insights_fallback_user)

    content = "nice short_url"
    comment = create_comment(conn, short_url.id, nil, content)
    delete_comment(conn, comment["id"])

    comments = short_url_comments(conn, short_url.id)
    short_url_comment = comments |> List.first()

    assert short_url_comment["user"]["id"] != comment["user"]["id"]
    assert short_url_comment["user"]["id"] |> Sanbase.Math.to_integer() == fallback_user.id

    assert short_url_comment["content"] != comment["content"]
    assert short_url_comment["content"] =~ "deleted"
  end

  test "create a subcomment", context do
    %{conn: conn, short_url: short_url} = context
    c1 = create_comment(conn, short_url.id, nil, "some content")
    c2 = create_comment(conn, short_url.id, c1["id"], "other content")
    create_comment(conn, short_url.id, c2["id"], "other content2")

    [comment, subcomment1, subcomment2] =
      short_url_comments(conn, short_url.id)
      |> Enum.sort_by(& &1["id"])

    assert comment["parentId"] == nil
    assert comment["rootParentId"] == nil

    assert subcomment1["parentId"] == comment["id"]
    assert subcomment1["rootParentId"] == comment["id"]

    assert subcomment2["parentId"] == subcomment1["id"]
    assert subcomment2["rootParentId"] == comment["id"]
  end

  defp create_comment(conn, short_url_id, parent_id, content) do
    mutation = """
    mutation {
      createComment(
        entityType: SHORT_URL
        id: #{short_url_id}
        parentId: #{parent_id || "null"}
        content: "#{content}") {
          id
          content
          shortUrlId
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
          shortUrlId
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
        shortUrlId
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

  defp short_url_comments(conn, short_url_id) do
    query = """
    {
      comments(
        entityType: SHORT_URL
        id: #{short_url_id}
        cursor: {type: BEFORE, datetime: "#{Timex.now()}"}) {
          id
          content
          shortUrlId
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
end
