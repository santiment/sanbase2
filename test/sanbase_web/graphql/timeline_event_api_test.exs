defmodule SanbaseWeb.Graphql.TimelineEventApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Insight.{Poll, Post}
  alias Sanbase.UserList
  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.Following.UserFollower

  setup do
    poll = Poll.find_or_insert_current_poll!()
    user = insert(:user, email: "test@example.com")
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user, poll: poll}
  end

  test "fetching timeline events by followed users", %{conn: conn, user: user, poll: poll} do
    user_to_follow = insert(:user)
    UserFollower.follow(user_to_follow.id, user.id)

    post =
      insert(:post,
        poll: poll,
        user: user_to_follow,
        state: Post.approved_state(),
        ready_state: Post.published()
      )

    event1 =
      insert(:timeline_event,
        post: post,
        user: user_to_follow,
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

    result = timeline_events_query(conn, "limit: 3")

    assert result |> hd() |> Map.get("events") |> length() == 3

    assert result |> hd() |> Map.get("cursor") == %{
             "after" => DateTime.to_iso8601(event3.inserted_at),
             "before" => DateTime.to_iso8601(event1.inserted_at)
           }
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
          }
          userTrigger {
            trigger {
              title,
              description
            }
          }
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

  defp default_trigger_settings_string_keys() do
    %{
      "type" => "daily_active_addresses",
      "target" => %{"slug" => "santiment"},
      "channel" => "telegram",
      "time_window" => "1d",
      "percent_threshold" => 300.0
    }
  end

  defp format_interpolated_json(string) do
    string
    |> String.replace(~r|\"|, ~S|\\"|)
    |> String.replace(~r|'|, ~S|"|)
  end
end
