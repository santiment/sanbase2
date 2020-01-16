defmodule SanbaseWeb.Graphql.TimelineEventApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Insight.Post
  alias Sanbase.UserList
  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.Auth.UserFollower

  setup do
    user = insert(:user, email: "test@example.com")
    conn = setup_jwt_auth(build_conn(), user)
    role_san_clan = insert(:role_san_clan)

    {:ok, conn: conn, user: user, role_san_clan: role_san_clan}
  end

  test "fetching timeline events by followed users", %{
    conn: conn,
    user: user,
    role_san_clan: role_san_clan
  } do
    user_to_follow = insert(:user)
    UserFollower.follow(user_to_follow.id, user.id)

    san_author = insert(:user)
    insert(:user_role, user: san_author, role: role_san_clan)

    post =
      insert(:post,
        user: user_to_follow,
        state: Post.approved_state(),
        ready_state: Post.published()
      )

    post2 =
      insert(:post,
        user: san_author,
        state: Post.approved_state(),
        ready_state: Post.published()
      )

    event1 =
      insert(:timeline_event,
        post: post,
        user: user_to_follow,
        event_type: TimelineEvent.publish_insight_type()
      )

    insert(:timeline_event,
      post: post2,
      user: san_author,
      event_type: TimelineEvent.publish_insight_type()
    )

    {:ok, user_list} =
      UserList.create_user_list(user_to_follow, %{name: "My Test List", is_public: true})

    insert(:timeline_event,
      user_list: user_list,
      user: user_to_follow,
      event_type: TimelineEvent.update_watchlist_type()
    )

    user_trigger =
      insert(:user_trigger,
        user: user_to_follow,
        trigger: %{
          is_public: true,
          settings: default_trigger_settings_string_keys(),
          title: "my trigger",
          description: "DAA going up 300%"
        }
      )

    event3 =
      insert(:timeline_event,
        user_trigger: user_trigger,
        user: user_to_follow,
        event_type: TimelineEvent.create_public_trigger_type()
      )

    result = timeline_events_query(conn, "limit: 5")

    assert result |> hd() |> Map.get("events") |> length() == 4
    assert result |> hd() |> Map.get("events") |> hd() |> Map.get("payload") == nil

    assert result |> hd() |> Map.get("cursor") == %{
             "after" => DateTime.to_iso8601(DateTime.truncate(event3.inserted_at, :second)),
             "before" => DateTime.to_iso8601(DateTime.truncate(event1.inserted_at, :second))
           }
  end

  test "get trigger fired event with signal payload", context do
    {_timeline_event, user_trigger} = create_timeline_event(context.user)

    trigger_fired_event =
      timeline_events_query(context.conn, "limit: 5")
      |> hd()
      |> Map.get("events")
      |> hd()

    assert trigger_fired_event["eventType"] == TimelineEvent.trigger_fired()
    assert trigger_fired_event["user"]["id"] |> String.to_integer() == context.user.id
    assert trigger_fired_event["payload"] == %{"default" => "some signal payload"}
    assert trigger_fired_event["trigger"]["id"] == user_trigger.id
    assert trigger_fired_event["likes"] == []
  end

  describe "likeTimelineEvent/unlikeTimelineEvent mutations" do
    test "like succeeds", context do
      user = insert(:user)
      {timeline_event, _user_trigger} = create_timeline_event(user)
      mutation = like_timeline_event_mutation(timeline_event.id)
      result = execute_mutation(context.conn, mutation, "likeTimelineEvent")

      assert result["likes"] == [%{"userId" => context.user.id}]
    end

    test "when user likes twice - returns error", context do
      user = insert(:user)
      {timeline_event, _user_trigger} = create_timeline_event(user)
      mutation = like_timeline_event_mutation(timeline_event.id)
      execute_mutation(context.conn, mutation, "likeTimelineEvent")
      error = execute_mutation_with_error(context.conn, mutation)

      assert error == "Can't vote for event with id #{timeline_event.id}"
    end

    test "when user has liked, he can unlike", context do
      user = insert(:user)
      {timeline_event, _user_trigger} = create_timeline_event(user)
      like_mutation = like_timeline_event_mutation(timeline_event.id)
      unlike_mutation = unlike_timeline_event_mutation(timeline_event.id)

      result1 = execute_mutation(context.conn, like_mutation, "likeTimelineEvent")
      assert result1["likes"] == [%{"userId" => context.user.id}]

      result2 = execute_mutation(context.conn, unlike_mutation, "unlikeTimelineEvent")
      assert result2["likes"] == []
    end

    test "when user has not liked, he can't unlike", context do
      user = insert(:user)
      {timeline_event, _user_trigger} = create_timeline_event(user)
      mutation = unlike_timeline_event_mutation(timeline_event.id)
      error = execute_mutation_with_error(context.conn, mutation)
      assert error == "Can't remove vote for event with id #{timeline_event.id}"
    end
  end

  defp timeline_events_query(conn, args_str) do
    query =
      ~s|
    {
      timelineEvents(#{args_str}) {
        cursor {
          after
          before
        }
        events {
          id
          likes {
            userId
          }
          eventType,
          insertedAt,
          user {
            id
          },
          userList {
            name
            isPublic
          }
          post {
            id
            tags { name }
          }
          trigger {
            id
            title
            description
          }
          payload
        }
      }
    }|
      |> format_interpolated_json()

    result =
      conn
      |> post("/graphql", query_skeleton(query, "timelineEvents"))
      |> json_response(200)

    result["data"]["timelineEvents"]
  end

  defp like_timeline_event_mutation(timeline_event_id) do
    """
    mutation {
      likeTimelineEvent(timelineEventId: #{timeline_event_id}) {
        id
        likes {
          userId
        }
      }
    }
    """
  end

  defp unlike_timeline_event_mutation(timeline_event_id) do
    """
    mutation {
      unlikeTimelineEvent(timelineEventId: #{timeline_event_id}) {
        id
        likes {
          userId
        }
      }
    }
    """
  end

  defp create_timeline_event(user) do
    user_trigger =
      insert(:user_trigger,
        user: user,
        trigger: %{
          is_public: true,
          settings: default_trigger_settings_string_keys(),
          title: "my trigger",
          description: "DAA going up 300%"
        }
      )

    timeline_event =
      insert(:timeline_event,
        user_trigger: user_trigger,
        user: user,
        event_type: TimelineEvent.trigger_fired(),
        payload: %{"default" => "some signal payload"}
      )

    {timeline_event, user_trigger}
  end

  defp default_trigger_settings_string_keys() do
    %{
      "type" => "daily_active_addresses",
      "target" => %{"slug" => "santiment"},
      "channel" => "telegram",
      "time_window" => "1d",
      "operation" => %{"percent_up" => 300.0}
    }
  end

  defp format_interpolated_json(string) do
    string
    |> String.replace(~r|\"|, ~S|\\"|)
    |> String.replace(~r|'|, ~S|"|)
  end
end
