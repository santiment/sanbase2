defmodule SanbaseWeb.Graphql.AppNotificationApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.AppNotifications
  alias Sanbase.Accounts.UserFollower
  alias Sanbase.UserList

  setup_all do
    subscriber = Sanbase.EventBus.AppNotificationsSubscriber

    EventBus.subscribe({subscriber, subscriber.topics()})

    on_exit(fn ->
      Sanbase.EventBus.drain_topics(subscriber.topics(), 10_000)
      EventBus.unsubscribe(subscriber)
    end)
  end

  setup do
    follower = insert(:user)
    author = insert(:user)
    conn = setup_jwt_auth(build_conn(), follower)

    [follower: follower, author: author, conn: conn]
  end

  describe "getCurrentUserNotifications query" do
    test "returns empty list when user has no notifications", %{conn: conn} do
      query = """
      {
        getCurrentUserNotifications {
          notifications {
            id
            type
            isRead
          }
          cursor {
            before
            after
          }
        }
      }
      """

      result = execute_query(conn, query, "getCurrentUserNotifications")

      assert result["notifications"] == []
      assert result["cursor"] == %{"after" => nil, "before" => nil}
    end

    test "returns notifications for current user", %{
      conn: conn,
      follower: follower,
      author: author
    } do
      watchlist = insert(:watchlist, user: author, is_public: true)

      {:ok, notification} =
        AppNotifications.create_notification(%{
          type: "create_watchlist",
          user_id: author.id,
          entity_type: "watchlist",
          entity_id: watchlist.id
        })

      {:ok, _} =
        AppNotifications.create_notification_read_status(%{
          notification_id: notification.id,
          user_id: follower.id
        })

      query = """
      {
        getCurrentUserNotifications {
          notifications {
            id
            type
            entityType
            entityId
            isBroadcast
            isRead
            readAt
          }
          cursor {
            before
            after
          }
        }
      }
      """

      result = execute_query(conn, query, "getCurrentUserNotifications")

      assert length(result["notifications"]) == 1
      [notif] = result["notifications"]
      assert notif["id"] == notification.id
      assert notif["type"] == "create_watchlist"
      assert notif["entityType"] == "watchlist"
      assert notif["entityId"] == watchlist.id
      assert notif["isRead"] == false
      assert notif["readAt"] == nil
    end

    test "respects limit parameter", %{conn: conn, follower: follower, author: author} do
      watchlists =
        for i <- 1..5 do
          insert(:watchlist, user: author, name: "Watchlist #{i}")
        end

      for watchlist <- watchlists do
        {:ok, notification} =
          AppNotifications.create_notification(%{
            type: "create_watchlist",
            user_id: author.id,
            entity_type: "watchlist",
            entity_id: watchlist.id
          })

        {:ok, _} =
          AppNotifications.create_notification_read_status(%{
            notification_id: notification.id,
            user_id: follower.id
          })
      end

      query = """
      {
        getCurrentUserNotifications(limit: 2) {
          notifications {
            id
          }
        }
      }
      """

      result = execute_query(conn, query, "getCurrentUserNotifications")
      assert length(result["notifications"]) == 2
    end

    test "supports cursor pagination", %{conn: conn, follower: follower, author: author} do
      for i <- 1..5 do
        watchlist = insert(:watchlist, user: author, name: "Watchlist #{i}")

        {:ok, notification} =
          AppNotifications.create_notification(%{
            type: "create_watchlist",
            user_id: author.id,
            entity_type: "watchlist",
            entity_id: watchlist.id
          })

        # Update the inserted_at to make the notifications have different timestamps so
        # the cursor pagination can work properly
        Ecto.Changeset.change(notification,
          inserted_at:
            DateTime.add(DateTime.utc_now(), -i * 60, :second) |> DateTime.truncate(:second)
        )
        |> Sanbase.Repo.update!()

        {:ok, _} =
          AppNotifications.create_notification_read_status(%{
            notification_id: notification.id,
            user_id: follower.id
          })
      end

      first_query = """
      {
        getCurrentUserNotifications(limit: 2) {
          notifications { id }
          cursor { before after }
        }
      }
      """

      first_result = execute_query(conn, first_query, "getCurrentUserNotifications")
      assert length(first_result["notifications"]) == 2
      cursor_before = first_result["cursor"]["before"]

      second_query = """
      {
        getCurrentUserNotifications(limit: 2, cursor: {type: BEFORE, datetime: "#{cursor_before}"}) {
          notifications { id }
        }
      }
      """

      second_result = execute_query(conn, second_query, "getCurrentUserNotifications")
      assert length(second_result["notifications"]) == 2

      first_ids = Enum.map(first_result["notifications"], & &1["id"])
      second_ids = Enum.map(second_result["notifications"], & &1["id"])
      assert MapSet.disjoint?(MapSet.new(first_ids), MapSet.new(second_ids))
    end

    test "requires authentication" do
      conn = build_conn()

      query = """
      {
        getCurrentUserNotifications {
          notifications { id }
        }
      }
      """

      error_msg = execute_query_with_error(conn, query)
      assert error_msg =~ "unauthorized"
    end
  end

  describe "setNotificationReadStatus mutation" do
    setup %{follower: follower, author: author} do
      watchlist = insert(:watchlist, user: author, is_public: true)

      {:ok, notification} =
        AppNotifications.create_notification(%{
          type: "create_watchlist",
          user_id: author.id,
          entity_type: "watchlist",
          entity_id: watchlist.id
        })

      {:ok, _} =
        AppNotifications.create_notification_read_status(%{
          notification_id: notification.id,
          user_id: follower.id
        })

      [notification: notification, watchlist: watchlist]
    end

    test "marks notification as read", %{conn: conn, notification: notification} do
      mutation = """
      mutation {
        setNotificationReadStatus(notificationId: #{notification.id}, isRead: true) {
          id
          isRead
          readAt
        }
      }
      """

      result = execute_mutation(conn, mutation, "setNotificationReadStatus")

      assert result["id"] == notification.id
      assert result["isRead"] == true
      assert result["readAt"] != nil
    end

    test "marks notification as unread", %{
      conn: conn,
      notification: notification,
      follower: follower
    } do
      AppNotifications.set_read_status(follower.id, notification.id, true)

      mutation = """
      mutation {
        setNotificationReadStatus(notificationId: #{notification.id}, isRead: false) {
          id
          isRead
          readAt
        }
      }
      """

      result = execute_mutation(conn, mutation, "setNotificationReadStatus")

      assert result["id"] == notification.id
      assert result["isRead"] == false
      assert result["readAt"] == nil
    end

    test "returns error for non-existent notification", %{conn: conn} do
      mutation = """
      mutation {
        setNotificationReadStatus(notificationId: 999999, isRead: true) {
          id
        }
      }
      """

      error_msg = execute_mutation_with_error(conn, mutation)
      assert error_msg =~ "not_found"
    end

    test "returns error when user has no access to notification", %{notification: notification} do
      other_user = insert(:user)
      other_conn = setup_jwt_auth(build_conn(), other_user)

      mutation = """
      mutation {
        setNotificationReadStatus(notificationId: #{notification.id}, isRead: true) {
          id
        }
      }
      """

      error_msg = execute_mutation_with_error(other_conn, mutation)
      assert error_msg =~ "not_found"
    end

    test "requires authentication", %{notification: notification} do
      conn = build_conn()

      mutation = """
      mutation {
        setNotificationReadStatus(notificationId: #{notification.id}, isRead: true) {
          id
        }
      }
      """

      error_msg = execute_mutation_with_error(conn, mutation)
      assert error_msg =~ "unauthorized"
    end
  end

  describe "integration: event-driven notifications via GraphQL" do
    setup %{author: author, follower: follower} do
      {:ok, _} = UserFollower.follow(author.id, follower.id)
      :ok
    end

    test "follower receives notification after author creates public watchlist", %{
      conn: conn,
      author: author
    } do
      query = """
      {
        getCurrentUserNotifications {
          notifications { id type entityType entityId isRead }
        }
      }
      """

      result = execute_query(conn, query, "getCurrentUserNotifications")
      assert result["notifications"] == []

      {:ok, watchlist} =
        UserList.create_user_list(author, %{name: "API Test Watchlist", is_public: true})

      :timer.sleep(100)

      result = execute_query(conn, query, "getCurrentUserNotifications")
      assert length(result["notifications"]) == 1

      [notif] = result["notifications"]
      assert notif["type"] == "create_watchlist"
      assert notif["entityType"] == "watchlist"
      assert notif["entityId"] == watchlist.id
      assert notif["isRead"] == false
    end

    test "follower can mark event-generated notification as read", %{conn: conn, author: author} do
      # Also test that create_user_list emits events
      {:ok, _watchlist} =
        UserList.create_user_list(author, %{name: "Markable Watchlist", is_public: true})

      :timer.sleep(100)

      query = """
      {
        getCurrentUserNotifications {
          notifications { id isRead }
        }
      }
      """

      result = execute_query(conn, query, "getCurrentUserNotifications")
      [notif] = result["notifications"]
      assert notif["isRead"] == false

      mutation = """
      mutation {
        setNotificationReadStatus(notificationId: #{notif["id"]}, isRead: true) {
          id
          isRead
          readAt
        }
      }
      """

      mutation_result = execute_mutation(conn, mutation, "setNotificationReadStatus")
      assert mutation_result["isRead"] == true
      assert mutation_result["readAt"] != nil

      result = execute_query(conn, query, "getCurrentUserNotifications")
      [updated_notif] = result["notifications"]
      assert updated_notif["isRead"] == true
    end
  end
end
