defmodule SanbaseWeb.Graphql.TimelineEventCommentApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Auth.UserFollower
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

    %{conn: conn, user: user, post: post, timeline_event: timeline_event}
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

  defp create_comment(conn, timeline_event_id, parent_id, content) do
    mutation = """
    mutation {
      createTimelineEventComment(
        timelineEventId: #{timeline_event_id}
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
    |> IO.inspect()
    |> get_in(["data", "createTimelineEventComment"])
  end

  defp timeline_event_comments(conn, timeline_event_id) do
    query = """
    {
      timelineEventComments(
        timelineEventId: #{timeline_event_id},
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
    |> IO.inspect()
    |> get_in(["data", "timelineEventComments"])
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
    |> IO.inspect()
    |> get_in(["data", "timelineEvent", "commentsCount"])
  end
end
