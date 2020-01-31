defmodule SanbaseWeb.Graphql.TimelineEventApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Insight.Post
  alias Sanbase.UserList
  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.Auth.UserFollower
  alias Sanbase.Comment.EntityComment

  @entity_type :timeline_event

  setup do
    user = insert(:user, email: "test@example.com")
    conn = setup_jwt_auth(build_conn(), user)
    role_san_clan = insert(:role_san_clan)

    {:ok, conn: conn, user: user, role_san_clan: role_san_clan}
  end

  test "timeline events with public entities by followed users or by san family are fetched", %{
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

  test "timeline events with private entities by followed users or by san family are not fetched",
       %{
         conn: conn,
         user: user,
         role_san_clan: role_san_clan
       } do
    user_to_follow = insert(:user)
    UserFollower.follow(user_to_follow.id, user.id)

    san_author = insert(:user)
    insert(:user_role, user: san_author, role: role_san_clan)

    {:ok, user_list} =
      UserList.create_user_list(user_to_follow, %{name: "My Test List", is_public: false})

    insert(:timeline_event,
      user_list: user_list,
      user: user_to_follow,
      event_type: TimelineEvent.update_watchlist_type()
    )

    user_trigger =
      insert(:user_trigger,
        user: san_author,
        trigger: %{
          is_public: false,
          settings: default_trigger_settings_string_keys(),
          title: "my trigger",
          description: "DAA going up 300%"
        }
      )

    insert(:timeline_event,
      user_trigger: user_trigger,
      user: san_author,
      event_type: TimelineEvent.create_public_trigger_type()
    )

    result = timeline_events_query(conn, "limit: 5")

    assert result |> hd() |> Map.get("events") |> length() == 0
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
    assert trigger_fired_event["votes"] == []
  end

  test "trigger fired event from public trigger from san family member is fetched",
       context do
    san_author = insert(:user)
    insert(:user_role, user: san_author, role: context.role_san_clan)

    user_trigger =
      insert(:user_trigger,
        user: san_author,
        trigger: %{
          is_public: true,
          settings: default_trigger_settings_string_keys(),
          title: "my trigger",
          description: "DAA going up 300%"
        }
      )

    insert(:timeline_event,
      user_trigger: user_trigger,
      user: san_author,
      event_type: TimelineEvent.trigger_fired(),
      payload: %{"default" => "some signal payload"}
    )

    assert timeline_events_query(context.conn, "limit: 5")
           |> hd()
           |> Map.get("events")
           |> length() == 1
  end

  test "trigger fired event from public trigger from followed user is fetched", context do
    user_to_follow = insert(:user)
    UserFollower.follow(user_to_follow.id, context.user.id)

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

    insert(:timeline_event,
      user_trigger: user_trigger,
      user: user_to_follow,
      event_type: TimelineEvent.trigger_fired(),
      payload: %{"default" => "some signal payload"}
    )

    assert timeline_events_query(context.conn, "limit: 5")
           |> hd()
           |> Map.get("events")
           |> length() == 1
  end

  test "trigger fired event from private trigger from san family member is not fetched",
       context do
    san_author = insert(:user)
    insert(:user_role, user: san_author, role: context.role_san_clan)

    user_trigger =
      insert(:user_trigger,
        user: san_author,
        trigger: %{
          is_public: false,
          settings: default_trigger_settings_string_keys(),
          title: "my trigger",
          description: "DAA going up 300%"
        }
      )

    insert(:timeline_event,
      user_trigger: user_trigger,
      user: san_author,
      event_type: TimelineEvent.trigger_fired(),
      payload: %{"default" => "some signal payload"}
    )

    assert timeline_events_query(context.conn, "limit: 5") |> hd() |> Map.get("events") == []
  end

  test "trigger fired event from private trigger from followed user is not fetched", context do
    user_to_follow = insert(:user)
    UserFollower.follow(user_to_follow.id, context.user.id)

    user_trigger =
      insert(:user_trigger,
        user: user_to_follow,
        trigger: %{
          is_public: false,
          settings: default_trigger_settings_string_keys(),
          title: "my trigger",
          description: "DAA going up 300%"
        }
      )

    insert(:timeline_event,
      user_trigger: user_trigger,
      user: user_to_follow,
      event_type: TimelineEvent.trigger_fired(),
      payload: %{"default" => "some signal payload"}
    )

    assert timeline_events_query(context.conn, "limit: 5") |> hd() |> Map.get("events") == []
  end

  test "timeline events for not logged in user", context do
    san_author = insert(:user)
    insert(:user_role, user: san_author, role: context.role_san_clan)

    post =
      insert(:post,
        user: san_author,
        state: Post.approved_state(),
        ready_state: Post.published()
      )

    insert(:timeline_event,
      post: post,
      user: san_author,
      event_type: TimelineEvent.publish_insight_type()
    )

    result = timeline_events_query(build_conn(), "limit: 5")

    assert result |> hd() |> Map.get("events") |> length() == 1
  end

  describe "upvoteTimelineEvent/downvoteTimelineEvent mutations" do
    test "upvote succeeds", context do
      user = insert(:user)
      {timeline_event, _user_trigger} = create_timeline_event(user)
      mutation = upvote_timeline_event_mutation(timeline_event.id)
      result = execute_mutation(context.conn, mutation, "upvoteTimelineEvent")

      assert result["votes"] == [%{"userId" => context.user.id}]
    end

    test "when user has upvoted, he can downvote", context do
      user = insert(:user)
      {timeline_event, _user_trigger} = create_timeline_event(user)
      upvote_mutation = upvote_timeline_event_mutation(timeline_event.id)
      downvote_mutation = downvote_timeline_event_mutation(timeline_event.id)

      result1 = execute_mutation(context.conn, upvote_mutation, "upvoteTimelineEvent")
      assert result1["votes"] == [%{"userId" => context.user.id}]

      result2 = execute_mutation(context.conn, downvote_mutation, "downvoteTimelineEvent")
      assert result2["votes"] == []
    end

    test "when user has not upvoted, he can't downvote", context do
      user = insert(:user)
      {timeline_event, _user_trigger} = create_timeline_event(user)
      mutation = downvote_timeline_event_mutation(timeline_event.id)
      error = execute_mutation_with_error(context.conn, mutation)
      assert error == "Can't remove vote for event with id #{timeline_event.id}"
    end
  end

  describe "order timeline events" do
    test "by datetime by default", context do
      events = create_test_events(context)
      result = timeline_events_query(context.conn, "limit: 3")

      assert event_ids(result) == [
               events.event_with_0_votes_and_0_comments_by_sanfam.id,
               events.event_with_1_votes_and_0_comments_by_sanfam.id,
               events.event_with_0_votes_and_1_comments_by_followed.id
             ]
    end

    # FIXME: order by: date, likes_count, datetime
    test "by number of votes", context do
      events = create_test_events(context)
      result = timeline_events_query(context.conn, "limit: 3, orderBy: VOTES")

      assert event_ids(result) == [
               events.event_with_1_votes_and_0_comments_by_sanfam.id,
               events.event_with_0_votes_and_0_comments_by_sanfam.id,
               events.event_with_0_votes_and_1_comments_by_followed.id
             ]
    end

    test "by number of comments", context do
      events = create_test_events(context)

      result = timeline_events_query(context.conn, "limit: 3, orderBy: COMMENTS")

      assert event_ids(result) == [
               events.event_with_0_votes_and_1_comments_by_followed.id,
               events.event_with_0_votes_and_0_comments_by_sanfam.id,
               events.event_with_1_votes_and_0_comments_by_sanfam.id
             ]
    end

    test "by author name", context do
      events = create_test_events(context)

      result = timeline_events_query(context.conn, "limit: 3, orderBy: AUTHOR")

      assert event_ids(result) == [
               events.event_with_0_votes_and_1_comments_by_followed.id,
               events.event_with_0_votes_and_0_comments_by_sanfam.id,
               events.event_with_1_votes_and_0_comments_by_sanfam.id
             ]
    end
  end

  describe "filter timeline events" do
    test "by san family and followed users (default)", context do
      events = create_test_events(context)

      result =
        timeline_events_query(context.conn, "filterBy: {author: SANFAM_AND_FOLLOWED}, limit: 3")

      assert event_ids(result) == [
               events.event_with_0_votes_and_0_comments_by_sanfam.id,
               events.event_with_1_votes_and_0_comments_by_sanfam.id,
               events.event_with_0_votes_and_1_comments_by_followed.id
             ]
    end

    test "by san family", context do
      events = create_test_events(context)
      result = timeline_events_query(context.conn, "filterBy: {author: SANFAM_ONLY}, limit: 3")

      assert event_ids(result) == [
               events.event_with_0_votes_and_0_comments_by_sanfam.id,
               events.event_with_1_votes_and_0_comments_by_sanfam.id
             ]
    end

    test "by followed users", context do
      events = create_test_events(context)
      result = timeline_events_query(context.conn, "filterBy: {author: FOLLOWED_ONLY}, limit: 3")

      assert event_ids(result) == [
               events.event_with_0_votes_and_1_comments_by_followed.id
             ]
    end

    test "current user's events", context do
      events = create_test_events(context)
      result = timeline_events_query(context.conn, "filterBy: {author: OWN_ONLY}, limit: 3")

      {:ok, user_list} =
        UserList.create_user_list(context.user.id(%{name: "My Test List", is_public: true}))

      watchlist_event =
        insert(:timeline_event,
          user_list: user_list,
          user: context.user.id,
          event_type: TimelineEvent.update_watchlist_type()
        )

      assert event_ids(result) == [watchlist_event.id]
    end

    test "by list of watchlists", context do
      user_to_follow = insert(:user)
      UserFollower.follow(user_to_follow.id, context.user.id)

      {:ok, user_list} =
        UserList.create_user_list(user_to_follow, %{name: "My Test List", is_public: true})

      watchlist_event =
        insert(:timeline_event,
          user_list: user_list,
          user: user_to_follow,
          event_type: TimelineEvent.update_watchlist_type()
        )

      events = create_test_events(context)

      result =
        timeline_events_query(
          context.conn,
          "filterBy: {author: SANFAM_AND_FOLLOWED, watchlists: [#{user_list.id}]}, limit: 3"
        )

      assert event_ids(result) == [
               watchlist_event.id
             ]
    end

    test "by list of assets", context do
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
          votes {
            userId
          }
          commentsCount,
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
      |> IO.inspect()
      |> json_response(200)
      |> IO.inspect()

    result["data"]["timelineEvents"]
  end

  defp upvote_timeline_event_mutation(timeline_event_id) do
    """
    mutation {
      upvoteTimelineEvent(timelineEventId: #{timeline_event_id}) {
        id
        votes {
          userId
        }
      }
    }
    """
  end

  defp downvote_timeline_event_mutation(timeline_event_id) do
    """
    mutation {
      downvoteTimelineEvent(timelineEventId: #{timeline_event_id}) {
        id
        votes {
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

  defp create_test_events(context) do
    # create event with 0 votes and 0 comments
    # create event with 1 votes and 0 comments
    # create event with 0 votes and 1 comments

    user = insert(:user)

    user_to_follow = insert(:user, username: "a")
    UserFollower.follow(user_to_follow.id, context.user.id)

    san_author2 = insert(:user, username: "b")
    insert(:user_role, user: san_author2, role: context.role_san_clan)

    post1 =
      insert(:post,
        user: user_to_follow,
        state: Post.approved_state(),
        ready_state: Post.published()
      )

    post2 =
      insert(:post,
        user: san_author2,
        state: Post.approved_state(),
        ready_state: Post.published()
      )

    post3 =
      insert(:post,
        user: san_author2,
        state: Post.approved_state(),
        ready_state: Post.published()
      )

    event_with_0_votes_and_1_comments_by_followed =
      insert(:timeline_event,
        post: post1,
        user: user_to_follow,
        event_type: TimelineEvent.publish_insight_type()
      )

    EntityComment.create_and_link(
      @entity_type,
      event_with_0_votes_and_1_comments_by_followed.id,
      user.id,
      nil,
      "some comment"
    )

    event_with_1_votes_and_0_comments_by_sanfam =
      insert(:timeline_event,
        post: post2,
        user: san_author2,
        event_type: TimelineEvent.publish_insight_type()
      )

    Sanbase.Vote.create(%{
      user_id: user.id,
      timeline_event_id: event_with_1_votes_and_0_comments_by_sanfam.id
    })

    event_with_0_votes_and_0_comments_by_sanfam =
      insert(:timeline_event,
        post: post3,
        user: san_author2,
        event_type: TimelineEvent.publish_insight_type()
      )

    %{
      event_with_0_votes_and_1_comments_by_followed:
        event_with_0_votes_and_1_comments_by_followed,
      event_with_1_votes_and_0_comments_by_sanfam: event_with_1_votes_and_0_comments_by_sanfam,
      event_with_0_votes_and_0_comments_by_sanfam: event_with_0_votes_and_0_comments_by_sanfam
    }
  end

  defp event_ids(result) do
    result
    |> hd()
    |> Map.get("events")
    |> Enum.map(&String.to_integer(&1["id"]))
  end

  defp format_interpolated_json(string) do
    string
    |> String.replace(~r|\"|, ~S|\\"|)
    |> String.replace(~r|'|, ~S|"|)
  end
end
