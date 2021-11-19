defmodule SanbaseWeb.Graphql.SeenEventApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.Accounts.UserFollower
  alias Sanbase.Timeline.SeenEvent

  @inight_type TimelineEvent.publish_insight_type()

  setup do
    user = insert(:user, email: "test@example.com")
    conn = setup_jwt_auth(build_conn(), user)
    _role_san_clan = insert(:role_san_clan)
    san_author = insert(:user)

    UserFollower.follow(san_author.id, user.id)

    insight = insert(:published_post, user: san_author)
    event1 = insert(:timeline_event, post: insight, user: san_author, event_type: @inight_type)

    {:ok, conn: conn, user: user, san_author: san_author, event1: event1}
  end

  test "Mark timeline event as seen", context do
    {:ok, seen_event} =
      SeenEvent.fetch_or_create(%{user_id: context.user.id, event_id: context.event1.id})

    last_seen_event_id = SeenEvent.last_seen_for_user(context.user.id)

    assert seen_event.event_id == last_seen_event_id
  end

  test "Update last seen event mutation", context do
    mutation = update_last_seen_mutation(context.event1.id)
    _result = execute_mutation(context.conn, mutation, "updateLastSeenEvent")
    last_seen_event_id = SeenEvent.last_seen_for_user(context.user.id)

    assert last_seen_event_id == context.event1.id
  end

  test "Fetch only new timeline events", context do
    result = execute_query(context.conn, new_timeline_events_query(), "timelineEvents")
    assert result == [%{"events" => [%{"id" => context.event1.id}]}]

    SeenEvent.fetch_or_create(%{user_id: context.user.id, event_id: context.event1.id})
    result = execute_query(context.conn, new_timeline_events_query(), "timelineEvents")
    assert result == [%{"events" => []}]
  end

  defp update_last_seen_mutation(event_id) do
    """
    mutation {
      updateLastSeenEvent(timelineEventId: #{event_id}) {
        eventId
        seenAt
      }
    }
    """
  end

  defp new_timeline_events_query() do
    """
    {
      timelineEvents(filterBy: {only_not_seen: true}, limit: 10) {
        events {
          id
        }
      }
    }
    """
  end
end
