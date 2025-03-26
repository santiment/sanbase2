defmodule SanbaseWeb.Graphql.DashboardsCommentsApiTest do
  use SanbaseWeb.ConnCase, async: true

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers
  import SanbaseWeb.CommentsApiHelper

  @opts [entity_type: :dashboard, extra_fields: ["dashboardId"]]
  setup do
    clean_task_supervisor_children()

    user = insert(:user)
    dashboard = insert(:dashboard, user: user)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, user: user, dashboard: dashboard}
  end

  test "commentsCount on dashboard", context do
    %{conn: conn, dashboard: dashboard} = context
    assert comments_count(conn, dashboard.id) == 0

    create_comment(conn, dashboard.id, "some content", @opts)
    assert comments_count(conn, dashboard.id) == 1

    create_comment(conn, dashboard.id, "some content", @opts)
    create_comment(conn, dashboard.id, "some content", @opts)
    create_comment(conn, dashboard.id, "some content", @opts)
    assert comments_count(conn, dashboard.id) == 4

    create_comment(conn, dashboard.id, "some content", @opts)
    assert comments_count(conn, dashboard.id) == 5
  end

  test "comment a dashboard", context do
    %{dashboard: dashboard, conn: conn, user: user} = context
    other_user_conn = setup_jwt_auth(build_conn(), insert(:user))

    content = "nice dashboard"

    comment = create_comment(conn, dashboard.id, content, @opts)
    comments = get_comments(other_user_conn, dashboard.id, @opts)

    assert comment["dashboardId"] |> Sanbase.Math.to_integer() == dashboard.id
    assert comment["content"] == content
    assert comment["insertedAt"] != nil
    assert comment["editedAt"] == nil
    assert comment["user"]["email"] == user.email
    assert length(comments) == 1
    assert comments |> List.first() |> Map.get("id") == comment["id"]
    assert comments |> hd() |> get_in(["user", "email"]) == "<email hidden>"
  end

  test "update a comment", context do
    %{conn: conn, dashboard: dashboard} = context

    content = "nice dashboard"
    new_content = "updated content"

    comment = create_comment(conn, dashboard.id, content, @opts)
    updated_comment = update_comment(conn, comment["id"], new_content, @opts)
    comments = get_comments(conn, dashboard.id, @opts)

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
    %{conn: conn, dashboard: dashboard} = context
    fallback_user = insert(:insights_fallback_user)

    content = "nice dashboard"
    comment = create_comment(conn, dashboard.id, content, @opts)
    delete_comment(conn, comment["id"], @opts)

    comments = get_comments(conn, dashboard.id, @opts)
    dashboard_comment = comments |> List.first()

    assert dashboard_comment["user"]["id"] != comment["user"]["id"]
    assert dashboard_comment["user"]["id"] |> Sanbase.Math.to_integer() == fallback_user.id

    assert dashboard_comment["content"] != comment["content"]
    assert dashboard_comment["content"] =~ "deleted"
  end

  test "create a subcomment", context do
    %{conn: conn, dashboard: dashboard} = context
    c1 = create_comment(conn, dashboard.id, "some content", @opts)

    opts = Keyword.put(@opts, :parent_id, c1["id"])
    c2 = create_comment(conn, dashboard.id, "other content", opts)

    opts = Keyword.put(@opts, :parent_id, c2["id"])
    create_comment(conn, dashboard.id, "other content2", opts)

    [comment, subcomment1, subcomment2] =
      get_comments(conn, dashboard.id, @opts)
      |> Enum.sort_by(& &1["id"])

    assert comment["parentId"] == nil
    assert comment["rootParentId"] == nil

    assert subcomment1["parentId"] == comment["id"]
    assert subcomment1["rootParentId"] == comment["id"]

    assert subcomment2["parentId"] == subcomment1["id"]
    assert subcomment2["rootParentId"] == comment["id"]
  end

  defp comments_count(conn, dashboard_id) do
    query = """
    {
      getDashboard(id: #{dashboard_id}) {
        commentsCount
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "getDashboard", "commentsCount"])
  end
end
