defmodule SanbaseWeb.Graphql.TimelineEventApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Insight.Post
  alias Sanbase.UserList
  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.Accounts.UserFollower
  alias Sanbase.Comments.EntityComment
  alias Sanbase.Alert.UserTrigger

  @entity_type :timeline_event

  setup do
    user = insert(:user, email: "test@example.com")
    conn = setup_jwt_auth(build_conn(), user)
    role_san_clan = insert(:role_san_clan)

    project = insert(:project, slug: "santiment", ticker: "SAN")
    project2 = insert(:project, slug: "ethereum", ticker: "ETH", name: "Ethereum")

    {:ok,
     conn: conn, user: user, role_san_clan: role_san_clan, project: project, project2: project2}
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
        event_type: TimelineEvent.publish_insight_type(),
        inserted_at: Timex.shift(Timex.now(), minutes: -5)
      )

    event2 =
      insert(:timeline_event,
        post: post2,
        user: san_author,
        event_type: TimelineEvent.publish_insight_type(),
        inserted_at: Timex.shift(Timex.now(), minutes: -4)
      )

    result = get_timeline_events(conn, "limit: 5")

    # Watchlist updates are ignored now
    assert result |> hd() |> Map.get("events") |> length() == 2
    assert result |> hd() |> Map.get("events") |> hd() |> Map.get("payload") == nil
    assert result |> hd() |> Map.get("events") |> hd() |> Map.get("data") == nil

    assert result |> hd() |> Map.get("cursor") == %{
             "after" =>
               DateTime.to_iso8601(event2.inserted_at |> DateTime.from_naive!("Etc/UTC")),
             "before" =>
               DateTime.to_iso8601(event1.inserted_at |> DateTime.from_naive!("Etc/UTC"))
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

    result = get_timeline_events(conn, "limit: 5")

    assert result |> hd() |> Map.get("events") |> length() == 0
  end

  test "get trigger fired event with signal payload", context do
    {_timeline_event, user_trigger} = create_timeline_event(context.user)

    trigger_fired_event =
      get_timeline_events(context.conn, "limit: 5")
      |> hd()
      |> Map.get("events")
      |> hd()

    assert trigger_fired_event["eventType"] == TimelineEvent.trigger_fired()
    assert trigger_fired_event["user"]["id"] |> String.to_integer() == context.user.id
    assert trigger_fired_event["payload"] == %{"default" => "some signal payload"}

    assert trigger_fired_event["data"] == %{
             "user_trigger_data" => %{"default" => %{"value" => 15}}
           }

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
      payload: %{"default" => "some signal payload"},
      data: %{"user_trigger_data" => %{"default" => %{"value" => 15}}}
    )

    assert get_timeline_events(context.conn, "limit: 5")
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
      payload: %{"default" => "some signal payload"},
      data: %{"user_trigger_data" => %{"default" => %{"value" => 15}}}
    )

    assert get_timeline_events(context.conn, "limit: 5")
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
      payload: %{"default" => "some signal payload"},
      data: %{"user_trigger_data" => %{"default" => %{"value" => 15}}}
    )

    assert get_timeline_events(context.conn, "limit: 5") |> hd() |> Map.get("events") == []
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
      payload: %{"default" => "some signal payload"},
      data: %{"user_trigger_data" => %{"default" => %{"value" => 15}}}
    )

    assert get_timeline_events(context.conn, "limit: 5") |> hd() |> Map.get("events") == []
  end

  describe "timeline events for not logged in user" do
    test "shows sanfamily insight", context do
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

      result = get_timeline_events(build_conn(), "limit: 5")

      assert result |> hd() |> Map.get("events") |> length() == 1
    end

    test "doesn't show private trigger that fired", context do
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
        payload: %{"default" => "some signal payload"},
        data: %{"user_trigger_data" => %{"default" => %{"value" => 15}}}
      )

      result = get_timeline_events(build_conn(), "limit: 5")

      assert result |> hd() |> Map.get("events") == []
    end
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

    test "when user has not upvoted, downvoting does nothing", context do
      user = insert(:user)
      {timeline_event, _user_trigger} = create_timeline_event(user)
      mutation = downvote_timeline_event_mutation(timeline_event.id)
      result = execute_mutation(context.conn, mutation, "downvoteTimelineEvent")
      assert result["votes"] == []
    end
  end

  describe "order timeline events" do
    test "by datetime by default", context do
      events = create_test_events(context)
      result = get_timeline_events(context.conn, "limit: 3")

      assert event_ids(result) == [
               events.event_with_0_votes_and_0_comments_by_sanfam.id,
               events.event_with_1_votes_and_0_comments_by_sanfam.id,
               events.event_with_0_votes_and_1_comments_by_followed.id
             ]
    end

    test "by date, by number of votes, by datetime", context do
      events = create_test_events(context)

      {:ok, _user_list} =
        UserList.create_user_list(context.user, %{name: "My Test List", is_public: true})

      result = get_timeline_events(context.conn, "limit: 4, orderBy: VOTES")

      assert event_ids(result) == [
               events.event_with_1_votes_and_0_comments_by_sanfam.id,
               events.event_with_0_votes_and_0_comments_by_sanfam.id,
               events.event_with_0_votes_and_1_comments_by_followed.id
             ]
    end

    test "by number of comments, by datetime", context do
      events = create_test_events(context)

      result = get_timeline_events(context.conn, "limit: 3, orderBy: COMMENTS")

      assert event_ids(result) == [
               events.event_with_0_votes_and_1_comments_by_followed.id,
               events.event_with_0_votes_and_0_comments_by_sanfam.id,
               events.event_with_1_votes_and_0_comments_by_sanfam.id
             ]
    end

    test "by author name, by datetime", context do
      events = create_test_events(context)

      result = get_timeline_events(context.conn, "limit: 3, orderBy: AUTHOR")

      assert event_ids(result) == [
               events.event_with_0_votes_and_1_comments_by_followed.id,
               events.event_with_0_votes_and_0_comments_by_sanfam.id,
               events.event_with_1_votes_and_0_comments_by_sanfam.id
             ]
    end
  end

  describe "filter timeline events" do
    test "by own, san family and followed users (default)", context do
      events = create_test_events(context)

      {:ok, _user_list} =
        UserList.create_user_list(context.user, %{name: "My Test List", is_public: true})

      result = get_timeline_events(context.conn, "filterBy: {author: ALL}, limit: 4")

      assert event_ids(result) == [
               events.event_with_0_votes_and_0_comments_by_sanfam.id,
               events.event_with_1_votes_and_0_comments_by_sanfam.id,
               events.event_with_0_votes_and_1_comments_by_followed.id
             ]
    end

    test "by san family", context do
      events = create_test_events(context)
      result = get_timeline_events(context.conn, "filterBy: {author: SANFAM}, limit: 3")

      assert event_ids(result) == [
               events.event_with_0_votes_and_0_comments_by_sanfam.id,
               events.event_with_1_votes_and_0_comments_by_sanfam.id
             ]
    end

    test "by followed users", context do
      events = create_test_events(context)
      result = get_timeline_events(context.conn, "filterBy: {author: FOLLOWED}, limit: 3")

      assert event_ids(result) == [
               events.event_with_0_votes_and_1_comments_by_followed.id
             ]
    end

    test "current user's events", context do
      create_test_events(context)

      {:ok, user_list} =
        UserList.create_user_list(context.user, %{name: "My Test List", is_public: true})

      _ =
        insert(:timeline_event,
          user_list: user_list,
          user: context.user,
          event_type: TimelineEvent.update_watchlist_type()
        )

      result = get_timeline_events(context.conn, "filterBy: {author: OWN}, limit: 3")
      # watchlist events are ignored now
      assert event_ids(result) == []
    end

    test "by list of watchlists", context do
      user_to_follow = insert(:user)
      UserFollower.follow(user_to_follow.id, context.user.id)

      {:ok, user_list} =
        UserList.create_user_list(user_to_follow, %{name: "My Test List", is_public: true})

      _ =
        insert(:timeline_event,
          user_list: user_list,
          user: user_to_follow,
          event_type: TimelineEvent.update_watchlist_type()
        )

      create_test_events(context)

      result =
        get_timeline_events(
          context.conn,
          "filterBy: {author: ALL, watchlists: [#{user_list.id}]}, limit: 3"
        )

      # watchlist update events are ignored now
      assert event_ids(result) == []
    end

    test "by list of assets", context do
      post =
        create_insight(context, %{
          tags: [build(:tag, name: String.downcase(context.project.ticker))]
        })

      {trigger1, trigger2, trigger3} = create_trigger(context)

      generic_setting_trigger_event = %{
        user_trigger: nil,
        user: context.user,
        event_type: TimelineEvent.trigger_fired(),
        payload: %{"default" => "some signal payload"},
        data: %{"user_trigger_data" => %{"default" => %{"value" => 15}}},
        inserted_at: NaiveDateTime.utc_now()
      }

      insight_event =
        insert(:timeline_event,
          post: post,
          user: context.user,
          event_type: TimelineEvent.publish_insight_type(),
          inserted_at: Timex.shift(NaiveDateTime.utc_now(), seconds: -4)
        )

      trigger1_event =
        insert(:timeline_event, %{
          generic_setting_trigger_event
          | user_trigger: trigger1,
            inserted_at: Timex.shift(NaiveDateTime.utc_now(), seconds: -3)
        })

      trigger2_event =
        insert(:timeline_event, %{
          generic_setting_trigger_event
          | user_trigger: trigger2,
            inserted_at: Timex.shift(NaiveDateTime.utc_now(), seconds: -2)
        })

      trigger3_event =
        insert(:timeline_event, %{
          generic_setting_trigger_event
          | user_trigger: trigger3,
            inserted_at: Timex.shift(NaiveDateTime.utc_now(), seconds: -1)
        })

      create_test_events(context)

      result =
        get_timeline_events(
          context.conn,
          "filterBy: {author: ALL, assets: [#{context.project.id}]}, limit: 5"
        )

      assert event_ids(result) == [
               trigger3_event.id,
               trigger2_event.id,
               trigger1_event.id,
               insight_event.id
             ]
    end

    test "by insight or pulse", context do
      pulse = create_insight(context, %{is_pulse: true, tags: []})
      not_pulse = create_insight(context, %{is_pulse: false, tags: []})

      pulse_event =
        insert(:timeline_event,
          post: pulse,
          user: context.user,
          event_type: TimelineEvent.publish_insight_type(),
          inserted_at: Timex.shift(NaiveDateTime.utc_now(), seconds: -4)
        )

      insight_event =
        insert(:timeline_event,
          post: not_pulse,
          user: context.user,
          event_type: TimelineEvent.publish_insight_type(),
          inserted_at: Timex.shift(NaiveDateTime.utc_now(), seconds: -3)
        )

      {trigger1, _trigger2, _trigger3} = create_trigger(context)

      generic_setting_trigger_event = %{
        user_trigger: nil,
        user: context.user,
        event_type: TimelineEvent.trigger_fired(),
        payload: %{"default" => "some signal payload"},
        data: %{"user_trigger_data" => %{"default" => %{"value" => 15}}},
        inserted_at: Timex.shift(NaiveDateTime.utc_now(), seconds: -2)
      }

      trigger1_event =
        insert(:timeline_event, %{generic_setting_trigger_event | user_trigger: trigger1})

      result =
        get_timeline_events(
          context.conn,
          "filterBy: {author: ALL, type: PULSE}, limit: 10"
        )

      assert event_ids(result) == [pulse_event.id]

      result =
        get_timeline_events(
          context.conn,
          "filterBy: {author: ALL, type: INSIGHT}, limit: 10"
        )

      assert event_ids(result) == [insight_event.id]

      result =
        get_timeline_events(
          context.conn,
          "filterBy: {author: ALL, type: ALERT}, limit: 10"
        )

      assert event_ids(result) == [trigger1_event.id]

      result =
        get_timeline_events(
          context.conn,
          "filterBy: {author: ALL}, limit: 10"
        )

      assert event_ids(result) == [trigger1_event.id, insight_event.id, pulse_event.id]
    end
  end

  describe "cursor filtered events" do
    test "cursor before", context do
      events = create_test_events(context)
      now = DateTime.utc_now()

      args_str = "cursor: " <> map_to_input_object_str(%{type: :before, datetime: now})

      events1 =
        get_timeline_events(
          context.conn,
          args_str
        )
        |> hd()
        |> Map.get("events")

      assert length(events1) == length(events |> Map.keys())

      args_str =
        "cursor: " <>
          map_to_input_object_str(%{type: :before, datetime: Timex.shift(now, seconds: -60)})

      events2 =
        get_timeline_events(
          context.conn,
          args_str
        )
        |> hd()
        |> Map.get("events")

      assert events2 == []
    end

    test "cursor after", context do
      events = create_test_events(context)
      now = DateTime.utc_now()

      args_str = "cursor: " <> map_to_input_object_str(%{type: :after, datetime: now})

      events1 =
        get_timeline_events(
          context.conn,
          args_str
        )
        |> hd()
        |> Map.get("events")

      assert events1 == []

      args_str =
        "cursor: " <>
          map_to_input_object_str(%{type: :after, datetime: Timex.shift(now, seconds: -60)})

      events2 =
        get_timeline_events(
          context.conn,
          args_str
        )
        |> hd()
        |> Map.get("events")

      assert length(events2) == length(events |> Map.keys())
    end
  end

  test "tags", context do
    {trigger1, _, _} = create_trigger(context)

    generic_setting_trigger_event = %{
      user_trigger: nil,
      user: context.user,
      event_type: TimelineEvent.trigger_fired(),
      payload: %{"default" => "some signal payload"},
      data: %{"user_trigger_data" => %{"default" => %{"value" => 15}}},
      inserted_at: NaiveDateTime.utc_now()
    }

    insert(:timeline_event, %{
      generic_setting_trigger_event
      | user_trigger: trigger1,
        inserted_at: Timex.shift(NaiveDateTime.utc_now(), seconds: -3)
    })

    create_test_events(context)

    result = get_timeline_events(context.conn, "limit: 4")

    events = result |> hd() |> Map.get("events")

    assert Enum.map(events, fn event -> event |> Map.get("tags") end) == [
             ["OWN", "ALERT"],
             ["SANFAM", "INSIGHT"],
             ["SANFAM", "INSIGHT"],
             ["FOLLOWED", "INSIGHT", "PULSE"]
           ]
  end

  test "timeline events api doesn't return data more than 6 months", context do
    user_to_follow = insert(:user)
    UserFollower.follow(user_to_follow.id, context.user.id)
    insight = insert(:post, user: user_to_follow)

    insert(:timeline_event,
      post: insight,
      user: user_to_follow,
      event_type: TimelineEvent.publish_insight_type(),
      inserted_at: Timex.shift(Timex.now(), months: -7)
    )

    result = get_timeline_events(context.conn, "limit: 5")

    assert result |> hd() |> Map.get("events") |> length() == 0

    insert(:timeline_event,
      post: insight,
      user: user_to_follow,
      event_type: TimelineEvent.publish_insight_type(),
      inserted_at: Timex.shift(Timex.now(), months: -5)
    )

    result = get_timeline_events(context.conn, "limit: 5")

    assert result |> hd() |> Map.get("events") |> length() == 1
  end

  defp get_timeline_events(conn, args_str) do
    query = ~s|
    {
      timelineEvents(#{args_str}) {
        cursor {
          after
          before
        }
        events {
          id
          tags
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
          data
        }
      }
    }|

    # |> format_interpolated_json()

    result =
      conn
      |> post("/graphql", query_skeleton(query, "timelineEvents"))
      |> json_response(200)

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
        payload: %{"default" => "some signal payload"},
        data: %{"user_trigger_data" => %{"default" => %{"value" => 15}}}
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
        ready_state: Post.published(),
        inserted_at: Timex.shift(NaiveDateTime.utc_now(), seconds: -10),
        is_pulse: true
      )

    post2 =
      insert(:post,
        user: san_author2,
        state: Post.approved_state(),
        ready_state: Post.published(),
        inserted_at: Timex.shift(NaiveDateTime.utc_now(), seconds: -9)
      )

    post3 =
      insert(:post,
        user: san_author2,
        state: Post.approved_state(),
        ready_state: Post.published(),
        inserted_at: Timex.shift(NaiveDateTime.utc_now(), seconds: -8)
      )

    event_with_0_votes_and_1_comments_by_followed =
      insert(:timeline_event,
        post: post1,
        user: user_to_follow,
        event_type: TimelineEvent.publish_insight_type(),
        inserted_at: Timex.shift(NaiveDateTime.utc_now(), seconds: -7)
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
        event_type: TimelineEvent.publish_insight_type(),
        inserted_at: Timex.shift(NaiveDateTime.utc_now(), seconds: -6)
      )

    Sanbase.Vote.create(%{
      user_id: user.id,
      timeline_event_id: event_with_1_votes_and_0_comments_by_sanfam.id
    })

    event_with_0_votes_and_0_comments_by_sanfam =
      insert(:timeline_event,
        post: post3,
        user: san_author2,
        event_type: TimelineEvent.publish_insight_type(),
        inserted_at: Timex.shift(NaiveDateTime.utc_now(), seconds: -5)
      )

    %{
      event_with_0_votes_and_1_comments_by_followed:
        event_with_0_votes_and_1_comments_by_followed,
      event_with_1_votes_and_0_comments_by_sanfam: event_with_1_votes_and_0_comments_by_sanfam,
      event_with_0_votes_and_0_comments_by_sanfam: event_with_0_votes_and_0_comments_by_sanfam
    }
  end

  defp create_insight(context, opts) do
    params =
      %{
        state: Post.approved_state(),
        ready_state: Post.published(),
        title: "Test insight",
        user: context.user,
        tags: [build(:tag, name: context.project.slug)],
        published_at: DateTime.to_naive(Timex.now())
      }
      |> Map.merge(opts)

    insert(:post, params)
  end

  def create_watchlist(context, create_opts \\ %{}, update_opts \\ %{}) do
    create_opts = %{user: context.user} |> Map.merge(create_opts)
    watchlist = insert(:watchlist, create_opts)

    update_opts =
      %{
        name: "My watch list of assets",
        id: watchlist.id,
        list_items: [%{project_id: context.project.id}, %{project_id: context.project2.id}]
      }
      |> Map.merge(update_opts)

    {:ok, watchlist} = UserList.update_user_list(context.user, update_opts)
    watchlist
  end

  def create_trigger(context) do
    generic_settings = %{
      title: "Generic title",
      is_public: false,
      cooldown: "1d",
      settings: %{}
    }

    trigger_settings = %{
      type: "price_volume_difference",
      target: %{slug: context.project.slug},
      channel: "telegram",
      threshold: 0.1
    }

    trending_words_settings = %{
      type: Sanbase.Alert.Trigger.TrendingWordsTriggerSettings.type(),
      channel: "telegram",
      operation: %{trending_word: true},
      target: %{word: [context.project.slug]}
    }

    trending_words_settings2 = %{
      type: Sanbase.Alert.Trigger.TrendingWordsTriggerSettings.type(),
      channel: "telegram",
      operation: %{trending_word: true},
      target: %{word: ["san"]}
    }

    {:ok, trigger1} =
      UserTrigger.create_user_trigger(context.user, %{
        generic_settings
        | settings: trigger_settings
      })

    {:ok, trigger2} =
      UserTrigger.create_user_trigger(context.user, %{
        generic_settings
        | settings: trending_words_settings
      })

    {:ok, trigger3} =
      UserTrigger.create_user_trigger(context.user, %{
        generic_settings
        | settings: trending_words_settings2
      })

    {trigger1, trigger2, trigger3}
  end

  defp event_ids(result) do
    result
    |> hd()
    |> Map.get("events", [])
    |> Enum.map(& &1["id"])
  end
end
