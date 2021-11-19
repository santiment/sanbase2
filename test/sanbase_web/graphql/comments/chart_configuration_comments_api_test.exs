defmodule SanbaseWeb.Graphql.ChartConfigurationCommentsApiTest do
  use SanbaseWeb.ConnCase, async: true

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.CommentsApiHelper

  @opts [entity_type: :chart_configuration, extra_fields: ["chartConfigurationId"]]

  setup do
    clean_task_supervisor_children()

    user = insert(:user)
    chart_configuration = insert(:chart_configuration, user: user)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, user: user, chart_configuration: chart_configuration}
  end

  test "commentsCount on chart configuration", context do
    %{conn: conn, chart_configuration: chart_configuration} = context
    assert comments_count(conn, chart_configuration.id) == 0

    create_comment(conn, chart_configuration.id, "some content", @opts)
    assert comments_count(conn, chart_configuration.id) == 1

    create_comment(conn, chart_configuration.id, "some content", @opts)
    create_comment(conn, chart_configuration.id, "some content", @opts)
    create_comment(conn, chart_configuration.id, "some content", @opts)
    assert comments_count(conn, chart_configuration.id) == 4

    create_comment(conn, chart_configuration.id, "some content", @opts)
    assert comments_count(conn, chart_configuration.id) == 5
  end

  test "comment a chart_configuration", context do
    %{chart_configuration: chart_configuration, conn: conn, user: user} = context
    other_user_conn = setup_jwt_auth(build_conn(), insert(:user))

    content = "nice chart_configuration"

    comment = create_comment(conn, chart_configuration.id, content, @opts)

    assert comment["chartConfigurationId"] |> Sanbase.Math.to_integer() == chart_configuration.id
    assert comment["content"] == content
    assert comment["insertedAt"] != nil
    assert comment["editedAt"] == nil
    assert comment["user"]["email"] == user.email

    comments = get_comments(other_user_conn, chart_configuration.id, @opts)

    assert length(comments) == 1
    assert comments |> List.first() |> Map.get("id") == comment["id"]
    assert comments |> hd() |> get_in(["user", "email"]) == "<email hidden>"
  end

  test "update a comment", context do
    %{conn: conn, chart_configuration: chart_configuration} = context

    content = "nice chart_configuration"
    new_content = "updated content"

    comment = create_comment(conn, chart_configuration.id, content, @opts)
    updated_comment = update_comment(conn, comment["id"], new_content, @opts)

    assert comment["editedAt"] == nil
    assert updated_comment["editedAt"] != nil

    edited_at = NaiveDateTime.from_iso8601!(updated_comment["editedAt"])
    assert Sanbase.TestUtils.datetime_close_to(edited_at, Timex.now(), 1, :seconds) == true

    assert comment["content"] == content
    assert updated_comment["content"] == new_content

    comments = get_comments(conn, chart_configuration.id, @opts)
    assert length(comments) == 1
    assert comments |> List.first() |> Map.get("content") == new_content
  end

  test "delete a comment", context do
    %{conn: conn, chart_configuration: chart_configuration} = context

    fallback_user = insert(:insights_fallback_user)

    content = "nice chart_configuration"

    comment = create_comment(conn, chart_configuration.id, content, @opts)

    delete_comment(conn, comment["id"], @opts)

    comments = get_comments(conn, chart_configuration.id, @opts)
    chart_config_comment = comments |> List.first()

    assert chart_config_comment["user"]["id"] != comment["user"]["id"]
    assert chart_config_comment["user"]["id"] |> Sanbase.Math.to_integer() == fallback_user.id
    assert chart_config_comment["content"] != comment["content"]
    assert chart_config_comment["content"] =~ "deleted"
  end

  test "create a subcomment", context do
    %{conn: conn, chart_configuration: chart_configuration} = context

    c1 = create_comment(conn, chart_configuration.id, "some content", @opts)

    opts = @opts |> Keyword.put(:parent_id, c1["id"])
    c2 = create_comment(conn, chart_configuration.id, "other content", opts)

    opts = @opts |> Keyword.put(:parent_id, c2["id"])
    create_comment(conn, chart_configuration.id, "other content2", opts)

    [comment, subcomment1, subcomment2] =
      get_comments(conn, chart_configuration.id, @opts)
      |> Enum.sort_by(& &1["id"])

    assert comment["parentId"] == nil
    assert comment["rootParentId"] == nil

    assert subcomment1["parentId"] == comment["id"]
    assert subcomment1["rootParentId"] == comment["id"]

    assert subcomment2["parentId"] == subcomment1["id"]
    assert subcomment2["rootParentId"] == comment["id"]
  end

  defp comments_count(conn, chart_configuration_id) do
    query = """
    {
      chartConfiguration(id: #{chart_configuration_id}) {
        commentsCount
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "chartConfiguration", "commentsCount"])
  end
end
