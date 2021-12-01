defmodule SanbaseWeb.Graphql.TimelineEventCommentApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Accounts.UserFollower
  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.Insight.Post

  setup do
    clean_task_supervisor_children()

    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    user_to_follow = insert(:user)
    UserFollower.follow(user_to_follow.id, user.id)

    post =
      insert(:post,
        user: user_to_follow,
        state: Post.approved_state(),
        ready_state: Post.published()
      )

    timeline_event =
      insert(:timeline_event,
        post: post,
        user: user_to_follow,
        event_type: TimelineEvent.publish_insight_type()
      )

    %{conn: conn, user: user, timeline_event: timeline_event}
  end

  test "commentsCount on timeline event", context do
    %{conn: conn, timeline_event: timeline_event} = context
    assert comments_count(conn, timeline_event.id) == 0

    create_comment(conn, timeline_event.id, nil, "some content")
    assert comments_count(conn, timeline_event.id) == 1

    create_comment(conn, timeline_event.id, nil, "some content")
    create_comment(conn, timeline_event.id, nil, "some content")
    create_comment(conn, timeline_event.id, nil, "some content")
    assert comments_count(conn, timeline_event.id) == 4

    create_comment(conn, timeline_event.id, nil, "some content")
    assert comments_count(conn, timeline_event.id) == 5
  end

  test "comment a timeline event", context do
    %{conn: conn, timeline_event: timeline_event} = context

    content = "alabala portokala"
    comment = create_comment(conn, timeline_event.id, nil, content)

    comments = timeline_event_comments(conn, timeline_event.id)

    assert comment["timelineEventId"] |> Sanbase.Math.to_integer() == timeline_event.id
    assert comment["content"] == content
    assert comment["insertedAt"] != nil
    assert comment["editedAt"] == nil
    assert length(comments) == 1
    assert comments |> List.first() |> Map.get("id") == comment["id"]
  end

  test "update a comment", context do
    %{conn: conn, timeline_event: timeline_event} = context

    content = "nice timeline_event"
    new_content = "updated content"

    comment = create_comment(conn, timeline_event.id, nil, content)
    updated_comment = update_comment(conn, comment["id"], new_content)
    comments = timeline_event_comments(conn, timeline_event.id)

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
    %{conn: conn, timeline_event: timeline_event} = context
    fallback_user = insert(:insights_fallback_user)

    content = "nice timeline_event"
    comment = create_comment(conn, timeline_event.id, nil, content)
    delete_comment(conn, comment["id"])

    comments = timeline_event_comments(conn, timeline_event.id)
    timeline_event_comment = comments |> List.first()

    assert timeline_event_comment["user"]["id"] != comment["user"]["id"]
    assert timeline_event_comment["user"]["id"] |> Sanbase.Math.to_integer() == fallback_user.id

    assert timeline_event_comment["content"] != comment["content"]
    assert timeline_event_comment["content"] =~ "deleted"
  end

  test "create a subcomment", context do
    %{conn: conn, timeline_event: timeline_event} = context
    c1 = create_comment(conn, timeline_event.id, nil, "some content")
    c2 = create_comment(conn, timeline_event.id, c1["id"], "other content")
    create_comment(conn, timeline_event.id, c2["id"], "other content2")

    [comment, subcomment1, subcomment2] =
      timeline_event_comments(conn, timeline_event.id)
      |> Enum.sort_by(& &1["id"])

    assert comment["parentId"] == nil
    assert comment["rootParentId"] == nil

    assert subcomment1["parentId"] == comment["id"]
    assert subcomment1["rootParentId"] == comment["id"]

    assert subcomment2["parentId"] == subcomment1["id"]
    assert subcomment2["rootParentId"] == comment["id"]
  end

  defp create_comment(conn, timeline_event_id, parent_id, content) do
    mutation = """
    mutation {
      createComment(
        entityType: TIMELINE_EVENT
        id: #{timeline_event_id}
        parentId: #{parent_id || "null"}
        content: "#{content}") {
          id
          content
          timelineEventId
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
          timelineEventId
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
        timelineEventId
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

  defp timeline_event_comments(conn, timeline_event_id) do
    query = """
    {
      comments(
        entityType: TIMELINE_EVENT,
        id: #{timeline_event_id},
        cursor: {type: BEFORE, datetime: "#{Timex.now()}"}) {
          id
          content
          timelineEventId
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
