defmodule SanbaseWeb.Graphql.AppNotificationApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.AppNotifications
  alias Sanbase.AppNotifications.NotificationMutedUser
  alias Sanbase.Accounts.UserFollower
  alias Sanbase.UserList

  setup_all do
    subscriber = Sanbase.EventBus.AppNotificationsSubscriber
    Sanbase.EventBus.subscribe_subscriber(subscriber)

    on_exit(fn ->
      Sanbase.EventBus.drain_topics(subscriber.topics(), 10_000)
      Sanbase.EventBus.unsubscribe_subscriber(subscriber)
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
          entity_name: watchlist.name,
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
            entity_name: watchlist.name,
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
      watchlists =
        for i <- 1..5 do
          insert(:watchlist, user: author, name: "Watchlist #{i}")
        end

      for {watchlist, i} <- Enum.with_index(watchlists, 1) do
        {:ok, notification} =
          AppNotifications.create_notification(%{
            type: "create_watchlist",
            user_id: author.id,
            entity_type: "watchlist",
            entity_name: watchlist.name,
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

      Process.sleep(100)
      #
      # There are 5 notifications:
      # n5, n4, n3, n2, n1 (n5 is the most recent, with inserted_at the closest to now)
      # The first query will fetch without cursor n5 and n4
      # The `cursor` values contain the first and last inserted_at timestamps of the fetched notifications
      #
      # The second query will fetch all with BEFORE the inserted_at of n4, which are n3, n2 and n1
      first_query = """
      {
        getCurrentUserNotifications(limit: 2) {
          notifications {
            id
            entityName
            entityType
            entityId
            insertedAt
            user {
              id
              username
              isSantimentTeamMember
            }
          }
          cursor { before after }
        }
      }
      """

      first_result = execute_query(conn, first_query, "getCurrentUserNotifications")
      assert length(first_result["notifications"]) == 2
      cursor_before = first_result["cursor"]["before"]

      second_query = """
      {
        getCurrentUserNotifications(limit: 20, cursor: {type: BEFORE, datetime: "#{cursor_before}"}) {
          notifications {
            id
            entityName
            entityType
            entityId
            insertedAt
            user {
              id
              username
              isSantimentTeamMember
            }
          }
          cursor { before after }
        }
      }
      """

      second_result = execute_query(conn, second_query, "getCurrentUserNotifications")
      assert length(second_result["notifications"]) == 3

      first_ids = Enum.map(first_result["notifications"], & &1["id"])
      second_ids = Enum.map(second_result["notifications"], & &1["id"])

      assert MapSet.disjoint?(MapSet.new(first_ids), MapSet.new(second_ids))

      first_entity_ids = Enum.map(first_result["notifications"], & &1["entityId"])
      second_entity_ids = Enum.map(second_result["notifications"], & &1["entityId"])

      assert MapSet.equal?(
               MapSet.new(first_entity_ids ++ second_entity_ids),
               MapSet.new(Enum.map(watchlists, & &1.id))
             )
    end

    test "returns per-type unread counts in stats, optionally filtered by cursor", %{
      conn: conn,
      follower: follower,
      author: author
    } do
      watchlists = for i <- 1..3, do: insert(:watchlist, user: author, name: "Watchlist #{i}")

      notifications =
        for {watchlist, i} <- Enum.with_index(watchlists, 1) do
          {:ok, notification} =
            AppNotifications.create_notification(%{
              type: if(i == 1, do: "create_watchlist", else: "update_watchlist"),
              user_id: author.id,
              entity_type: "watchlist",
              entity_name: watchlist.name,
              entity_id: watchlist.id
            })

          notification =
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

          notification
        end

      # Mark the create_watchlist notification (index 0, most recent) as read
      AppNotifications.set_read_status(follower.id, hd(notifications).id, true)

      # No cursor: all 3 notifications counted
      # create_watchlist: 0 unread (1 read), update_watchlist: 2 unread
      query = """
      {
        getCurrentUserNotifications {
          stats { type unreadCount }
        }
      }
      """

      result = execute_query(conn, query, "getCurrentUserNotifications")
      stats = result["stats"] |> Map.new(&{&1["type"], &1["unreadCount"]})
      assert stats["create_watchlist"] == 0
      assert stats["update_watchlist"] == 2

      # Cursor BEFORE the second notification (index 1, second most recent update_watchlist):
      # only the oldest notification (index 2, update_watchlist, unread) is counted
      cursor_dt = Enum.at(notifications, 1).inserted_at |> DateTime.to_iso8601()

      query_with_cursor = """
      {
        getCurrentUserNotifications(cursor: {type: BEFORE, datetime: "#{cursor_dt}"}) {
          stats { type unreadCount }
        }
      }
      """

      result = execute_query(conn, query_with_cursor, "getCurrentUserNotifications")
      stats = result["stats"] |> Map.new(&{&1["type"], &1["unreadCount"]})
      assert stats["update_watchlist"] == 1
      refute Map.has_key?(stats, "create_watchlist")
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
          entity_name: watchlist.name,
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

  describe "markAllNotificationsAsRead mutation" do
    setup %{follower: follower, author: author} do
      notifications =
        for i <- 1..3 do
          {:ok, notification} =
            AppNotifications.create_notification(%{
              type: "create_watchlist",
              user_id: author.id,
              entity_type: "watchlist",
              entity_name: "Watchlist #{i}",
              entity_id: i
            })

          {:ok, _} =
            AppNotifications.create_notification_read_status(%{
              notification_id: notification.id,
              user_id: follower.id
            })

          notification
        end

      [notifications: notifications]
    end

    test "marks all unread notifications as read", %{conn: conn} do
      mutation = """
      mutation {
        markAllNotificationsAsRead {
          updatedCount
        }
      }
      """

      result = execute_mutation(conn, mutation, "markAllNotificationsAsRead")
      assert result["updatedCount"] == 3

      # Verify all are read
      query = """
      {
        getCurrentUserNotifications {
          stats { type unreadCount }
        }
      }
      """

      result = execute_query(conn, query, "getCurrentUserNotifications")
      stats = result["stats"] |> Map.new(&{&1["type"], &1["unreadCount"]})
      assert stats["create_watchlist"] == 0
    end

    test "returns zero when no unread notifications exist", %{
      conn: conn,
      follower: follower,
      notifications: notifications
    } do
      # Mark all as read first
      for n <- notifications do
        AppNotifications.set_read_status(follower.id, n.id, true)
      end

      mutation = """
      mutation {
        markAllNotificationsAsRead {
          updatedCount
        }
      }
      """

      result = execute_mutation(conn, mutation, "markAllNotificationsAsRead")
      assert result["updatedCount"] == 0
    end

    test "requires authentication" do
      conn = build_conn()

      mutation = """
      mutation {
        markAllNotificationsAsRead {
          updatedCount
        }
      }
      """

      error_msg = execute_mutation_with_error(conn, mutation)
      assert error_msg =~ "unauthorized"
    end
  end

  describe "muteUserNotifications / unmuteUserNotifications / getNotificationMutedUsers" do
    test "mute, list, and unmute a user", %{conn: conn, author: author} do
      mute_mutation = """
      mutation {
        muteUserNotifications(userId: "#{author.id}") {
          id
        }
      }
      """

      result = execute_mutation(conn, mute_mutation, "muteUserNotifications")
      assert result["id"] == to_string(author.id)

      list_query = """
      {
        getNotificationMutedUsers {
          id
        }
      }
      """

      result = execute_query(conn, list_query, "getNotificationMutedUsers")
      assert length(result) == 1
      assert hd(result)["id"] == to_string(author.id)

      unmute_mutation = """
      mutation {
        unmuteUserNotifications(userId: "#{author.id}") {
          id
        }
      }
      """

      result = execute_mutation(conn, unmute_mutation, "unmuteUserNotifications")
      assert result["id"] == to_string(author.id)

      result = execute_query(conn, list_query, "getNotificationMutedUsers")
      assert result == []
    end

    test "mute requires authentication", %{author: author} do
      conn = build_conn()

      mutation = """
      mutation {
        muteUserNotifications(userId: "#{author.id}") {
          id
        }
      }
      """

      error_msg = execute_mutation_with_error(conn, mutation)
      assert error_msg =~ "unauthorized"
    end

    test "muted user's notifications are not delivered via event", %{
      conn: conn,
      follower: follower,
      author: author
    } do
      {:ok, _} = UserFollower.follow(author.id, follower.id)
      {:ok, _} = NotificationMutedUser.mute(follower.id, author.id)

      {:ok, _watchlist} =
        UserList.create_user_list(author, %{name: "Muted API Watchlist", is_public: true})

      :timer.sleep(100)

      query = """
      {
        getCurrentUserNotifications {
          notifications { id type }
        }
      }
      """

      result = execute_query(conn, query, "getCurrentUserNotifications")
      assert result["notifications"] == []
    end
  end

  describe "integration: event-driven notifications via GraphQL" do
    setup %{author: author, follower: follower} do
      {:ok, _} = UserFollower.follow(author.id, follower.id)
      :ok
    end

    test "user receives follow notification when followed", %{
      author: author
    } do
      new_follower = insert(:user)
      author_conn = setup_jwt_auth(build_conn(), author)

      query = """
      {
        getCurrentUserNotifications {
          notifications { id type entityType entityId isRead user { id } }
        }
      }
      """

      result = execute_query(author_conn, query, "getCurrentUserNotifications")
      initial_count = length(result["notifications"])

      {:ok, _} = UserFollower.follow(author.id, new_follower.id)

      :timer.sleep(100)

      result = execute_query(author_conn, query, "getCurrentUserNotifications")
      assert length(result["notifications"]) == initial_count + 1

      notif =
        Enum.find(
          result["notifications"],
          &(&1["type"] == "new_follower" && &1["user"]["id"] == "#{new_follower.id}")
        )

      assert notif["entityType"] == "user"
      assert notif["entityId"] == author.id
      assert notif["isRead"] == false
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
