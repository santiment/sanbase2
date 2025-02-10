defmodule SanbaseWeb.Graphql.WatchlistCommentsApiTest do
  use SanbaseWeb.ConnCase, async: true

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.CommentsApiHelper
  import SanbaseWeb.Graphql.TestHelpers

  @opts [entity_type: :watchlist, extra_fields: ["watchlistId"]]
  setup do
    clean_task_supervisor_children()

    user = insert(:user)
    watchlist = insert(:watchlist, user: user)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, user: user, watchlist: watchlist}
  end

  test "commentsCount on watchlist", context do
    %{conn: conn, watchlist: watchlist} = context
    assert comments_count(conn, watchlist.id) == 0

    create_comment(conn, watchlist.id, "some content", @opts)
    assert comments_count(conn, watchlist.id) == 1

    create_comment(conn, watchlist.id, "some content", @opts)
    create_comment(conn, watchlist.id, "some content", @opts)
    create_comment(conn, watchlist.id, "some content", @opts)
    assert comments_count(conn, watchlist.id) == 4

    create_comment(conn, watchlist.id, "some content", @opts)
    assert comments_count(conn, watchlist.id) == 5
  end

  test "comment a watchlist", context do
    %{watchlist: watchlist, conn: conn, user: user} = context
    other_user_conn = setup_jwt_auth(build_conn(), insert(:user))

    content = "nice watchlist"

    comment = create_comment(conn, watchlist.id, content, @opts)
    comments = get_comments(other_user_conn, watchlist.id, @opts)

    assert Sanbase.Math.to_integer(comment["watchlistId"]) == watchlist.id
    assert comment["content"] == content
    assert comment["insertedAt"] != nil
    assert comment["editedAt"] == nil
    assert comment["user"]["email"] == user.email
    assert length(comments) == 1
    assert comments |> List.first() |> Map.get("id") == comment["id"]
    assert comments |> hd() |> get_in(["user", "email"]) == "<email hidden>"
  end

  test "update a comment", context do
    %{conn: conn, watchlist: watchlist} = context

    content = "nice watchlist"
    new_content = "updated content"

    comment = create_comment(conn, watchlist.id, content, @opts)
    updated_comment = update_comment(conn, comment["id"], new_content, @opts)
    comments = get_comments(conn, watchlist.id, @opts)

    assert comment["editedAt"] == nil
    assert updated_comment["editedAt"] != nil

    edited_at = NaiveDateTime.from_iso8601!(updated_comment["editedAt"])
    assert Sanbase.TestUtils.datetime_close_to(edited_at, DateTime.utc_now(), 1, :seconds) == true

    assert comment["content"] == content
    assert updated_comment["content"] == new_content
    assert length(comments) == 1
    assert comments |> List.first() |> Map.get("content") == new_content
  end

  test "delete a comment", context do
    %{conn: conn, watchlist: watchlist} = context
    fallback_user = insert(:insights_fallback_user)

    content = "nice watchlist"
    comment = create_comment(conn, watchlist.id, content, @opts)
    delete_comment(conn, comment["id"], @opts)

    comments = get_comments(conn, watchlist.id, @opts)
    watchlist_comment = List.first(comments)

    assert watchlist_comment["user"]["id"] != comment["user"]["id"]
    assert Sanbase.Math.to_integer(watchlist_comment["user"]["id"]) == fallback_user.id

    assert watchlist_comment["content"] != comment["content"]
    assert watchlist_comment["content"] =~ "deleted"
  end

  test "create a subcomment", context do
    %{conn: conn, watchlist: watchlist} = context
    c1 = create_comment(conn, watchlist.id, "some content", @opts)

    opts = Keyword.put(@opts, :parent_id, c1["id"])
    c2 = create_comment(conn, watchlist.id, "other content", opts)

    opts = Keyword.put(@opts, :parent_id, c2["id"])
    create_comment(conn, watchlist.id, "other content2", opts)

    [comment, subcomment1, subcomment2] =
      conn
      |> get_comments(watchlist.id, @opts)
      |> Enum.sort_by(& &1["id"])

    assert comment["parentId"] == nil
    assert comment["rootParentId"] == nil

    assert subcomment1["parentId"] == comment["id"]
    assert subcomment1["rootParentId"] == comment["id"]

    assert subcomment2["parentId"] == subcomment1["id"]
    assert subcomment2["rootParentId"] == comment["id"]
  end

  defp comments_count(conn, watchlist_id) do
    query = """
    {
      watchlist(id: #{watchlist_id}) {
        commentsCount
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "watchlist", "commentsCount"])
  end
end
