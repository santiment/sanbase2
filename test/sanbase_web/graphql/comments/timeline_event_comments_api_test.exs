defmodule SanbaseWeb.GraphqlTimelineEventCommentsApiTest do
  use SanbaseWeb.ConnCase, async: true

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.CommentsApiHelper

  @opts [entity_type: :timeline_event, extra_fields: ["timelineEventId"]]
  setup do
    clean_task_supervisor_children()

    user = insert(:user)
    watchlist = insert(:watchlist, user: user)

    timeline_event =
      insert(:timeline_event,
        user_list: watchlist,
        user: user,
        event_type: Sanbase.Timeline.TimelineEvent.update_watchlist_type()
      )

    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, user: user, timeline_event: timeline_event}
  end

  test "commentsCount on timeline_event", context do
    %{conn: conn, timeline_event: timeline_event} = context
    assert comments_count(conn, timeline_event.id) == 0

    create_comment(conn, timeline_event.id, "some content", @opts)
    assert comments_count(conn, timeline_event.id) == 1

    create_comment(conn, timeline_event.id, "some content", @opts)
    create_comment(conn, timeline_event.id, "some content", @opts)
    create_comment(conn, timeline_event.id, "some content", @opts)
    assert comments_count(conn, timeline_event.id) == 4

    create_comment(conn, timeline_event.id, "some content", @opts)
    assert comments_count(conn, timeline_event.id) == 5
  end

  test "comment a timeline_event", context do
    %{timeline_event: timeline_event, conn: conn, user: user} = context
    other_user_conn = setup_jwt_auth(build_conn(), insert(:user))

    content = "nice timeline_event"

    comment = create_comment(conn, timeline_event.id, content, @opts)
    comments = get_comments(other_user_conn, timeline_event.id, @opts)

    assert comment["timelineEventId"] |> Sanbase.Math.to_integer() == timeline_event.id
    assert comment["content"] == content
    assert comment["insertedAt"] != nil
    assert comment["editedAt"] == nil
    assert comment["user"]["email"] == user.email
    assert length(comments) == 1
    assert comments |> List.first() |> Map.get("id") == comment["id"]
    assert comments |> hd() |> get_in(["user", "email"]) == "<email hidden>"
  end

  test "update a comment", context do
    %{conn: conn, timeline_event: timeline_event} = context

    content = "nice timeline_event"
    new_content = "updated content"

    comment = create_comment(conn, timeline_event.id, content, @opts)
    updated_comment = update_comment(conn, comment["id"], new_content, @opts)
    comments = get_comments(conn, timeline_event.id, @opts)

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
    %{conn: conn, timeline_event: timeline_event} = context
    fallback_user = insert(:insights_fallback_user)

    content = "nice timeline_event"
    comment = create_comment(conn, timeline_event.id, content, @opts)
    delete_comment(conn, comment["id"], @opts)

    comments = get_comments(conn, timeline_event.id, @opts)
    timeline_event_comment = comments |> List.first()

    assert timeline_event_comment["user"]["id"] != comment["user"]["id"]
    assert timeline_event_comment["user"]["id"] |> Sanbase.Math.to_integer() == fallback_user.id

    assert timeline_event_comment["content"] != comment["content"]
    assert timeline_event_comment["content"] =~ "deleted"
  end

  test "create a subcomment", context do
    %{conn: conn, timeline_event: timeline_event} = context
    c1 = create_comment(conn, timeline_event.id, "some content", @opts)

    opts = Keyword.put(@opts, :parent_id, c1["id"])
    c2 = create_comment(conn, timeline_event.id, "other content", opts)

    opts = Keyword.put(@opts, :parent_id, c2["id"])
    create_comment(conn, timeline_event.id, "other content2", opts)

    [comment, subcomment1, subcomment2] =
      get_comments(conn, timeline_event.id, @opts)
      |> Enum.sort_by(& &1["id"])

    assert comment["parentId"] == nil
    assert comment["rootParentId"] == nil

    assert subcomment1["parentId"] == comment["id"]
    assert subcomment1["rootParentId"] == comment["id"]

    assert subcomment2["parentId"] == subcomment1["id"]
    assert subcomment2["rootParentId"] == comment["id"]
  end

  defp comments_count(conn, timeline_event_id) do
    query = """
    {
      timelineEvent(id: #{timeline_event_id}) {
        commentsCount
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "timelineEvent", "commentsCount"])
  end
end
