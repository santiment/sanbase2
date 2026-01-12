defmodule Sanbase.AppNotificationsTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.AppNotifications
  alias Sanbase.AppNotifications.Notification
  alias Sanbase.Accounts.UserFollower
  alias Sanbase.Insight.Post
  alias Sanbase.UserList

  setup_all do
    subscriber = Sanbase.EventBus.AppNotificationsSubscriber

    EventBus.subscribe({subscriber, subscriber.topics()})

    on_exit(fn ->
      Sanbase.EventBus.drain_topics(subscriber.topics(), 10_000)
      EventBus.unsubscribe(subscriber)
    end)
  end

  describe "create_notification/1" do
    test "creates notification with valid attrs" do
      user = insert(:user)
      watchlist = insert(:watchlist, user: user)

      attrs = %{
        type: "create_watchlist",
        user_id: user.id,
        entity_type: "watchlist",
        entity_id: watchlist.id,
        is_broadcast: false,
        is_system_generated: false
      }

      assert {:ok, %Notification{} = notification} = AppNotifications.create_notification(attrs)
      assert notification.type == "create_watchlist"
      assert notification.user_id == user.id
      assert notification.entity_type == "watchlist"
      assert notification.entity_id == watchlist.id
    end

    test "returns error with missing required fields" do
      assert {:error, changeset} = AppNotifications.create_notification(%{})
      assert "can't be blank" in errors_on(changeset).type
    end
  end

  describe "list_notifications_for_user/2" do
    setup do
      follower = insert(:user)
      author = insert(:user)

      watchlists =
        for i <- 1..5 do
          insert(:watchlist, user: author, name: "Watchlist #{i}")
        end

      notifications =
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

          notification
        end

      [follower: follower, author: author, watchlists: watchlists, notifications: notifications]
    end

    test "returns notifications for user", %{follower: follower, notifications: notifications} do
      result = AppNotifications.list_notifications_for_user(follower.id)

      assert length(result) == 5

      notification_ids = Enum.map(result, & &1.id)
      expected_ids = Enum.map(notifications, & &1.id)
      assert Enum.sort(notification_ids) == Enum.sort(expected_ids)
    end

    test "respects limit option", %{follower: follower} do
      result = AppNotifications.list_notifications_for_user(follower.id, limit: 2)
      assert length(result) == 2
    end

    test "returns empty list when user has no notifications" do
      other_user = insert(:user)
      result = AppNotifications.list_notifications_for_user(other_user.id)
      assert result == []
    end

    test "orders by inserted_at desc", %{follower: follower} do
      result = AppNotifications.list_notifications_for_user(follower.id)
      timestamps = Enum.map(result, & &1.inserted_at)
      assert timestamps == Enum.sort(timestamps, {:desc, DateTime})
    end
  end

  describe "get_notification_for_user/2" do
    setup do
      follower = insert(:user)
      author = insert(:user)
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

      [follower: follower, author: author, watchlist: watchlist, notification: notification]
    end

    test "returns notification for user", %{follower: follower, notification: notification} do
      assert {:ok, result} =
               AppNotifications.get_notification_for_user(follower.id, notification.id)

      assert result.id == notification.id
      assert result.type == "create_watchlist"
    end

    test "returns not_found for missing notification", %{follower: follower} do
      assert {:error, :not_found} =
               AppNotifications.get_notification_for_user(follower.id, 999_999)
    end

    test "returns not_found when user has no access to notification", %{
      notification: notification
    } do
      other_user = insert(:user)

      assert {:error, :not_found} =
               AppNotifications.get_notification_for_user(other_user.id, notification.id)
    end
  end

  describe "set_read_status/3" do
    setup do
      follower = insert(:user)
      author = insert(:user)
      watchlist = insert(:watchlist, user: author)

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

      [follower: follower, notification: notification]
    end

    test "marks notification as read", %{follower: follower, notification: notification} do
      assert {:ok, :updated} =
               AppNotifications.set_read_status(follower.id, notification.id, true)

      {:ok, updated} = AppNotifications.get_notification_for_user(follower.id, notification.id)
      assert updated.read_at != nil
    end

    test "marks notification as unread", %{follower: follower, notification: notification} do
      AppNotifications.set_read_status(follower.id, notification.id, true)

      assert {:ok, :updated} =
               AppNotifications.set_read_status(follower.id, notification.id, false)

      {:ok, updated} = AppNotifications.get_notification_for_user(follower.id, notification.id)
      assert updated.read_at == nil
    end

    test "returns error for non-existent notification", %{follower: follower} do
      assert {:error, :not_found} = AppNotifications.set_read_status(follower.id, 999_999, true)
    end

    test "does not overwrite existing read_at when marking as read again", %{
      follower: follower,
      notification: notification
    } do
      assert {:ok, :updated} =
               AppNotifications.set_read_status(follower.id, notification.id, true)

      {:ok, first_read} = AppNotifications.get_notification_for_user(follower.id, notification.id)
      original_read_at = first_read.read_at

      :timer.sleep(100)

      assert {:ok, :updated} =
               AppNotifications.set_read_status(follower.id, notification.id, true)

      {:ok, second_read} =
        AppNotifications.get_notification_for_user(follower.id, notification.id)

      assert second_read.read_at == original_read_at
    end
  end

  describe "wrap_with_cursor/1" do
    test "returns empty result for empty list" do
      assert {:ok, %{notifications: [], cursor: %{}}} = AppNotifications.wrap_with_cursor([])
    end

    test "returns cursor info for notifications" do
      now = DateTime.utc_now(:second)
      before = DateTime.add(now, -60, :second)

      notifications = [
        %{id: 1, inserted_at: now},
        %{id: 2, inserted_at: before}
      ]

      assert {:ok, result} = AppNotifications.wrap_with_cursor(notifications)

      assert result.notifications == notifications
      assert result.cursor.after == now
      assert result.cursor.before == before
    end
  end

  describe "events are emitted on actions" do
    setup do
      author = insert(:user)
      follower = insert(:user)

      {:ok, _} = UserFollower.follow(author.id, follower.id)

      [author: author, follower: follower]
    end

    # publish_insight tests

    test "publish_insight creates notification for followers", %{
      author: author,
      follower: follower
    } do
      post = insert(:post, user: author)

      assert AppNotifications.list_notifications_for_user(follower.id) == []

      {:ok, published_post} = Post.publish(post.id, author.id)

      :timer.sleep(100)

      notifications = AppNotifications.list_notifications_for_user(follower.id)
      assert length(notifications) == 1

      [notification] = notifications
      assert notification.type == "publish_insight"
      assert notification.entity_type == "insight"
      assert notification.entity_id == published_post.id
      assert notification.user_id == author.id
    end

    test "publish_insight does not notify non-followers", %{author: author} do
      non_follower = insert(:user)
      post = insert(:post, user: author)

      {:ok, _} = Post.publish(post.id, author.id)

      :timer.sleep(100)

      notifications = AppNotifications.list_notifications_for_user(non_follower.id)
      assert notifications == []
    end

    # create_watchlist tests

    test "create_watchlist with is_public=true creates notification", %{
      author: author,
      follower: follower
    } do
      assert AppNotifications.list_notifications_for_user(follower.id) == []

      {:ok, watchlist} =
        UserList.create_user_list(author, %{name: "Public Watchlist", is_public: true})

      :timer.sleep(100)

      notifications = AppNotifications.list_notifications_for_user(follower.id)
      assert length(notifications) == 1

      [notification] = notifications
      assert notification.type == "create_watchlist"
      assert notification.entity_type == "watchlist"
      assert notification.entity_id == watchlist.id
      assert notification.user_id == author.id
    end

    test "create_watchlist with is_public=false does not create notification", %{
      author: author,
      follower: follower
    } do
      {:ok, _watchlist} =
        UserList.create_user_list(author, %{name: "Private Watchlist", is_public: false})

      :timer.sleep(100)

      notifications = AppNotifications.list_notifications_for_user(follower.id)
      assert notifications == []
    end

    # update_watchlist tests - is_public change

    test "update_watchlist changing is_public from false to true creates notification", %{
      author: author,
      follower: follower
    } do
      {:ok, watchlist} =
        UserList.create_user_list(author, %{name: "Watchlist", is_public: false})

      :timer.sleep(100)
      assert AppNotifications.list_notifications_for_user(follower.id) == []

      {:ok, _updated} =
        UserList.update_user_list(author, %{id: watchlist.id, is_public: true})

      :timer.sleep(100)

      notifications = AppNotifications.list_notifications_for_user(follower.id)
      assert length(notifications) == 1

      [notification] = notifications
      assert notification.type == "update_watchlist"
      assert notification.entity_id == watchlist.id
      assert "is_public" in notification.json_data["changed_fields"]
    end

    test "update_watchlist changing is_public from true to false does not create notification", %{
      author: author,
      follower: follower
    } do
      {:ok, watchlist} =
        UserList.create_user_list(author, %{name: "Watchlist", is_public: true})

      :timer.sleep(100)

      # Clear the create notification
      initial_count = length(AppNotifications.list_notifications_for_user(follower.id))

      {:ok, _updated} =
        UserList.update_user_list(author, %{id: watchlist.id, is_public: false})

      :timer.sleep(100)

      # No new notification should be created (watchlist is now private)
      final_count = length(AppNotifications.list_notifications_for_user(follower.id))
      assert final_count == initial_count
    end

    # update_watchlist tests - function change

    test "update_watchlist changing function creates notification", %{
      author: author,
      follower: follower
    } do
      {:ok, watchlist} =
        UserList.create_user_list(author, %{name: "Watchlist", is_public: true})

      :timer.sleep(100)

      initial_count = length(AppNotifications.list_notifications_for_user(follower.id))

      new_function = %{"name" => "slugs", "args" => %{"slugs" => ["bitcoin", "ethereum"]}}

      {:ok, _updated} =
        UserList.update_user_list(author, %{id: watchlist.id, function: new_function})

      :timer.sleep(100)

      notifications = AppNotifications.list_notifications_for_user(follower.id)
      assert length(notifications) == initial_count + 1

      [notification | _] = notifications
      assert notification.type == "update_watchlist"
      assert "function" in notification.json_data["changed_fields"]
    end

    # update_watchlist tests - list_items change

    test "update_watchlist adding list_items creates notification", %{
      author: author,
      follower: follower
    } do
      project = insert(:random_erc20_project)

      {:ok, watchlist} =
        UserList.create_user_list(author, %{name: "Watchlist", is_public: true})

      :timer.sleep(200)

      initial_count = length(AppNotifications.list_notifications_for_user(follower.id))

      {:ok, _updated} =
        UserList.add_user_list_items(author, %{
          id: watchlist.id,
          list_items: [%{project_id: project.id}]
        })

      :timer.sleep(200)

      notifications = AppNotifications.list_notifications_for_user(follower.id)
      assert length(notifications) == initial_count + 1

      # Find the update notification specifically
      update_notification =
        Enum.find(notifications, fn n -> n.type == "update_watchlist" end)

      assert update_notification != nil
      assert "list_items" in update_notification.json_data["changed_fields"]
      assert update_notification.json_data["changes"] != nil
    end

    test "update_watchlist removing list_items creates notification", %{
      author: author,
      follower: follower
    } do
      project = insert(:random_erc20_project)

      {:ok, watchlist} =
        UserList.create_user_list(author, %{
          name: "Watchlist",
          is_public: true,
          list_items: [%{project_id: project.id}]
        })

      :timer.sleep(200)

      initial_count = length(AppNotifications.list_notifications_for_user(follower.id))

      {:ok, _updated} =
        UserList.remove_user_list_items(author, %{
          id: watchlist.id,
          list_items: [%{project_id: project.id}]
        })

      :timer.sleep(200)

      notifications = AppNotifications.list_notifications_for_user(follower.id)
      assert length(notifications) == initial_count + 1

      # Find the update notification specifically
      update_notification =
        Enum.find(notifications, fn n -> n.type == "update_watchlist" end)

      assert update_notification != nil
      assert "list_items" in update_notification.json_data["changed_fields"]
    end

    # update_watchlist tests - non-notifying changes

    test "update_watchlist changing only name does not create notification", %{
      author: author,
      follower: follower
    } do
      {:ok, watchlist} =
        UserList.create_user_list(author, %{name: "Watchlist", is_public: true})

      :timer.sleep(100)

      initial_count = length(AppNotifications.list_notifications_for_user(follower.id))

      {:ok, _updated} =
        UserList.update_user_list(author, %{id: watchlist.id, name: "New Name"})

      :timer.sleep(100)

      final_count = length(AppNotifications.list_notifications_for_user(follower.id))
      assert final_count == initial_count
    end

    test "update_watchlist changing only description does not create notification", %{
      author: author,
      follower: follower
    } do
      {:ok, watchlist} =
        UserList.create_user_list(author, %{name: "Watchlist", is_public: true})

      :timer.sleep(100)

      initial_count = length(AppNotifications.list_notifications_for_user(follower.id))

      {:ok, _updated} =
        UserList.update_user_list(author, %{id: watchlist.id, description: "New description"})

      :timer.sleep(100)

      final_count = length(AppNotifications.list_notifications_for_user(follower.id))
      assert final_count == initial_count
    end

    # Private watchlist updates should not create notifications

    test "update_watchlist on private watchlist does not create notification", %{
      author: author,
      follower: follower
    } do
      project = insert(:random_erc20_project)

      {:ok, watchlist} =
        UserList.create_user_list(author, %{name: "Private Watchlist", is_public: false})

      :timer.sleep(100)

      assert AppNotifications.list_notifications_for_user(follower.id) == []

      # Add items to private watchlist
      {:ok, _updated} =
        UserList.add_user_list_items(author, %{
          id: watchlist.id,
          list_items: [%{project_id: project.id}]
        })

      :timer.sleep(100)

      # Still no notifications
      assert AppNotifications.list_notifications_for_user(follower.id) == []
    end

    # Multiple followers test

    test "multiple followers receive notifications for same action", %{
      author: author,
      follower: follower
    } do
      follower2 = insert(:user)
      {:ok, _} = UserFollower.follow(author.id, follower2.id)

      {:ok, watchlist} =
        UserList.create_user_list(author, %{name: "Shared Watchlist", is_public: true})

      :timer.sleep(100)

      notifications1 = AppNotifications.list_notifications_for_user(follower.id)
      notifications2 = AppNotifications.list_notifications_for_user(follower2.id)

      assert length(notifications1) == 1
      assert length(notifications2) == 1

      assert hd(notifications1).entity_id == watchlist.id
      assert hd(notifications2).entity_id == watchlist.id
    end
  end
end
