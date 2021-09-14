defmodule SanbaseWeb.Graphql.InsightCommentApiTest do
  use SanbaseWeb.ConnCase, async: true

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.CommentsApiHelper

  @opts [entity_type: :insight, extra_fields: ["insightId"]]

  setup do
    clean_task_supervisor_children()

    user = insert(:user)
    post = insert(:post)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, user: user, post: post}
  end

  describe "Insight creation rate limit" do
    setup do
      # on exit revert to the original test env that is higher than
      # on prod so we avoid hitting rate limits
      env = Application.get_env(:sanbase, Sanbase.Comment)
      on_exit(fn -> Application.put_env(:sanbase, Sanbase.Comment, env) end)

      []
    end

    test "creation rate limit per minute is enforced", context do
      %{conn: conn, post: post} = context

      env = Application.get_env(:sanbase, Sanbase.Comment)
      env = Keyword.put(env, :creation_limit_minute, 2)
      Application.put_env(:sanbase, Sanbase.Comment, env)

      assert %{"id" => _} = create_comment(conn, post.id, "some content", @opts)
      assert %{"id" => _} = create_comment(conn, post.id, "some content", @opts)

      create_comment_with_error(conn, post.id, "some content", @opts) =~
        "Cannot create more than 2 comment per minute"
    end

    test "creation rate limit per hour is enforced", context do
      %{conn: conn, post: post} = context

      env = Application.get_env(:sanbase, Sanbase.Comment)
      env = Keyword.put(env, :creation_limit_hour, 1)
      Application.put_env(:sanbase, Sanbase.Comment, env)

      assert %{"id" => _} = create_comment(conn, post.id, "some content", @opts)

      create_comment_with_error(conn, post.id, "some content", @opts) =~
        "Cannot create more than 1 comment per hour"
    end

    test "creation rate limit per day is enforced", context do
      %{conn: conn, post: post} = context

      env = Application.get_env(:sanbase, Sanbase.Comment)
      env = Keyword.put(env, :creation_limit_day, 1)
      Application.put_env(:sanbase, Sanbase.Comment, env)

      assert %{"id" => _} = create_comment(conn, post.id, "some content", @opts)

      create_comment_with_error(conn, post.id, "some content", @opts) =~
        "Cannot create more than 1 comment per day"
    end
  end

  test "commentsCount on insights", context do
    %{conn: conn, post: post} = context
    assert comments_count(conn, post.id) == 0

    create_comment(conn, post.id, "some content", @opts)
    assert comments_count(conn, post.id) == 1

    create_comment(conn, post.id, "some content", @opts)
    create_comment(conn, post.id, "some content", @opts)
    create_comment(conn, post.id, "some content", @opts)
    assert comments_count(conn, post.id) == 4

    create_comment(conn, post.id, "some content", @opts)
    assert comments_count(conn, post.id) == 5
  end

  test "comment an insight", context do
    %{post: post, conn: conn, user: user} = context
    other_user_conn = setup_jwt_auth(build_conn(), insert(:user))

    content = "nice post"

    comment = create_comment(conn, post.id, content, @opts)

    comments = get_comments(other_user_conn, post.id, @opts)

    assert comment["insightId"] |> Sanbase.Math.to_integer() == post.id
    assert comment["content"] == content
    assert comment["insertedAt"] != nil
    assert comment["editedAt"] == nil
    assert comment["user"]["email"] == user.email
    assert length(comments) == 1
    assert comments |> List.first() |> Map.get("id") == comment["id"]
    assert comments |> hd() |> get_in(["user", "email"]) == "<email hidden>"
  end

  test "update a comment", context do
    %{conn: conn, post: post} = context

    content = "nice post"
    new_content = "updated content"

    comment = create_comment(conn, post.id, content, @opts)
    updated_comment = update_comment(conn, comment["id"], new_content, @opts)
    comments = get_comments(conn, post.id, @opts)

    assert comment["editedAt"] == nil
    assert updated_comment["editedAt"] != nil
    edited_at = NaiveDateTime.from_iso8601!(updated_comment["editedAt"])
    assert Sanbase.TestUtils.datetime_close_to(edited_at, Timex.now(), 1, :seconds) == true

    assert comment["content"] == content
    assert updated_comment["content"] == new_content
    assert length(comments) == 1
    assert comments |> List.first() |> Map.get("content") == new_content
  end

  test "delete a comment", context do
    %{conn: conn, post: post} = context
    fallback_user = insert(:insights_fallback_user)

    content = "nice post"
    comment = create_comment(conn, post.id, content, @opts)
    delete_comment(conn, comment["id"], @opts)

    comments = get_comments(conn, post.id, @opts)
    post_comment = comments |> List.first()

    assert post_comment["user"]["id"] != comment["user"]["id"]
    assert post_comment["user"]["id"] |> Sanbase.Math.to_integer() == fallback_user.id

    assert post_comment["content"] != comment["content"]
    assert post_comment["content"] =~ "deleted"
  end

  test "create a subcomment", context do
    %{conn: conn, post: post} = context
    c1 = create_comment(conn, post.id, "some content", @opts)

    opts = Keyword.put(@opts, :parent_id, c1["id"])
    c2 = create_comment(conn, post.id, "other content", opts)

    opts = Keyword.put(@opts, :parent_id, c2["id"])
    create_comment(conn, post.id, "other content2", opts)

    [comment, subcomment1, subcomment2] =
      get_comments(conn, post.id, @opts)
      |> Enum.sort_by(&(&1["id"] |> String.to_integer()))

    assert comment["parentId"] == nil
    assert comment["rootParentId"] == nil

    assert subcomment1["parentId"] == comment["id"]
    assert subcomment1["rootParentId"] == comment["id"]

    assert subcomment2["parentId"] == subcomment1["id"]
    assert subcomment2["rootParentId"] == comment["id"]
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
