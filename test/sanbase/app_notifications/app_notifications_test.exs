defmodule Sanbase.AppNotificationsTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.AppNotifications
  alias Sanbase.AppNotifications.Notification
  alias Sanbase.AppNotifications.NotificationMutedUser
  alias Sanbase.Accounts.UserFollower
  alias Sanbase.Comments.EntityComment
  alias Sanbase.Insight.Post
  alias Sanbase.UserList
  alias Sanbase.Vote

  setup_all do
    subscriber = Sanbase.EventBus.AppNotificationsSubscriber
    Sanbase.EventBus.subscribe_subscriber(subscriber)

    on_exit(fn ->
      Sanbase.EventBus.drain_topics(subscriber.topics(), 10_000)
      Sanbase.EventBus.unsubscribe_subscriber(subscriber)
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

  describe "list_notifications_for_user/2 with types filter" do
    setup do
      user = insert(:user)
      author = insert(:user)

      for {type, entity_type, entity_id} <- [
            {"create_watchlist", "watchlist", 1},
            {"publish_insight", "insight", 2},
            {"create_comment", "insight", 2}
          ] do
        {:ok, notification} =
          AppNotifications.create_notification(%{
            type: type,
            user_id: author.id,
            entity_type: entity_type,
            entity_id: entity_id
          })

        {:ok, _} =
          AppNotifications.create_notification_read_status(%{
            notification_id: notification.id,
            user_id: user.id
          })
      end

      [user: user]
    end

    test "filters by a single type", %{user: user} do
      result = AppNotifications.list_notifications_for_user(user.id, types: ["create_watchlist"])
      assert length(result) == 1
      assert hd(result).type == "create_watchlist"
    end

    test "filters by multiple types", %{user: user} do
      result =
        AppNotifications.list_notifications_for_user(user.id,
          types: ["create_watchlist", "publish_insight"]
        )

      assert length(result) == 2
      returned_types = result |> Enum.map(& &1.type) |> MapSet.new()
      assert returned_types == MapSet.new(["create_watchlist", "publish_insight"])
    end

    test "returns all notifications when no types filter given", %{user: user} do
      result = AppNotifications.list_notifications_for_user(user.id)
      assert length(result) == 3
    end

    test "returns empty list when no notifications match the given types", %{user: user} do
      result =
        AppNotifications.list_notifications_for_user(user.id, types: ["alert_triggered"])

      assert result == []
    end
  end

  describe "list_available_notification_types_for_user/1" do
    test "returns distinct notification types for the user" do
      user = insert(:user)
      author = insert(:user)

      for {type, entity_id} <- [
            {"create_watchlist", 1},
            {"publish_insight", 2},
            {"create_watchlist", 3}
          ] do
        {:ok, notification} =
          AppNotifications.create_notification(%{
            type: type,
            user_id: author.id,
            entity_type: "watchlist",
            entity_id: entity_id
          })

        {:ok, _} =
          AppNotifications.create_notification_read_status(%{
            notification_id: notification.id,
            user_id: user.id
          })
      end

      types = AppNotifications.list_available_notification_types_for_user(user.id)
      assert Enum.sort(types) == ["create_watchlist", "publish_insight"]
    end

    test "returns empty list when user has no notifications" do
      user = insert(:user)
      assert AppNotifications.list_available_notification_types_for_user(user.id) == []
    end

    test "does not include types from deleted notifications" do
      user = insert(:user)
      author = insert(:user)

      {:ok, notification} =
        AppNotifications.create_notification(%{
          type: "create_watchlist",
          user_id: author.id,
          entity_type: "watchlist",
          entity_id: 1,
          is_deleted: true
        })

      {:ok, _} =
        AppNotifications.create_notification_read_status(%{
          notification_id: notification.id,
          user_id: user.id
        })

      assert AppNotifications.list_available_notification_types_for_user(user.id) == []
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

    test "create_comment does not emit notification when user comments their own entity",
         _context do
      author = insert(:user)
      post = insert(:post, user: author)
      {:ok, published_post} = Post.publish(post.id, author.id)

      content = String.duplicate("a", 160)

      {:ok, _comment} =
        EntityComment.create_and_link(:insight, published_post.id, author.id, nil, content)

      :timer.sleep(100)

      owner_notifications = AppNotifications.list_notifications_for_user(author.id)
      assert length(owner_notifications) == 0
    end

    test "create_comment notifies only entity owner with preview", %{
      author: author
    } do
      commenter = insert(:user)
      other_user = insert(:user)
      post = insert(:post, user: author)

      {:ok, published_post} = Post.publish(post.id, author.id)

      initial_count = length(AppNotifications.list_notifications_for_user(author.id))

      content = String.duplicate("a", 160)

      {:ok, _comment} =
        EntityComment.create_and_link(:insight, published_post.id, commenter.id, nil, content)

      :timer.sleep(100)

      owner_notifications = AppNotifications.list_notifications_for_user(author.id)
      assert length(owner_notifications) == initial_count + 1

      notification = Enum.find(owner_notifications, &(&1.type == "create_comment"))
      assert notification.entity_type == "insight"
      assert notification.entity_id == published_post.id
      assert notification.user_id == commenter.id
      assert notification.json_data["comment_preview"] == String.slice(content, 0, 150)

      assert AppNotifications.list_notifications_for_user(commenter.id) == []
      assert AppNotifications.list_notifications_for_user(other_user.id) == []
    end

    test "create_vote does not notify when user votes on their own entity" do
      author = insert(:user)

      {:ok, watchlist} =
        UserList.create_user_list(author, %{name: "Vote target", is_public: true})

      {:ok, _vote} = Vote.create(%{user_id: author.id, watchlist_id: watchlist.id})

      :timer.sleep(100)

      owner_notifications = AppNotifications.list_notifications_for_user(author.id)
      assert length(owner_notifications) == 0
    end

    test "create_vote notifies only entity owner", %{author: author} do
      voter = insert(:user)
      other_user = insert(:user)

      {:ok, watchlist} =
        UserList.create_user_list(author, %{name: "Vote target", is_public: true})

      initial_count = length(AppNotifications.list_notifications_for_user(author.id))

      {:ok, _vote} = Vote.create(%{user_id: voter.id, watchlist_id: watchlist.id})

      :timer.sleep(100)

      owner_notifications = AppNotifications.list_notifications_for_user(author.id)
      assert length(owner_notifications) == initial_count + 1

      notification = Enum.find(owner_notifications, &(&1.type == "create_vote"))
      assert notification.entity_type == "watchlist"
      assert notification.entity_id == watchlist.id
      assert notification.user_id == voter.id
      assert notification.json_data == %{}

      assert AppNotifications.list_notifications_for_user(voter.id) == []
      assert AppNotifications.list_notifications_for_user(other_user.id) == []
    end

    test "creating multiple votes quickly emits only one notification", %{author: author} do
      voter = insert(:user)

      {:ok, watchlist} =
        UserList.create_user_list(author, %{name: "Vote target", is_public: true})

      {:ok, _vote} = Vote.create(%{user_id: voter.id, watchlist_id: watchlist.id})
      {:ok, _vote} = Vote.create(%{user_id: voter.id, watchlist_id: watchlist.id})
      {:ok, _vote} = Vote.create(%{user_id: voter.id, watchlist_id: watchlist.id})

      Sanbase.EventBus.AppNotificationsSubscriber.topics()
      |> Sanbase.EventBus.drain_topics()

      owner_notifications = AppNotifications.list_notifications_for_user(author.id, limit: 20)

      create_vote_notifications =
        Enum.filter(owner_notifications, fn n ->
          n.type == "create_vote" and n.entity_type == "watchlist" and n.entity_id == watchlist.id
        end)

      assert length(create_vote_notifications) == 1
    end

    test "alert_triggered notifies alert owner", %{} do
      user = insert(:user)
      alert_title = "Price Alert"

      user_trigger =
        insert(:user_trigger,
          user: user,
          trigger: %{
            title: alert_title,
            is_public: false,
            settings: %{
              "type" => "metric_signal",
              "metric" => "price_usd",
              "target" => %{"slug" => "santiment"},
              "channel" => "telegram",
              "time_window" => "1d",
              "operation" => %{"percent_up" => 20.0}
            }
          }
        )

      Sanbase.EventBus.notify(%{
        topic: :alert_events,
        data: %{
          event_type: :alert_triggered,
          user_id: user.id,
          alert_id: user_trigger.id,
          alert_title: alert_title
        }
      })

      :timer.sleep(200)

      notifications = AppNotifications.list_notifications_for_user(user.id)
      assert length(notifications) == 1

      [notification] = notifications
      assert notification.type == "alert_triggered"
      assert notification.entity_type == "user_trigger"
      assert notification.entity_id == user_trigger.id
      assert notification.entity_name == alert_title
      assert notification.user_id == user.id
      assert notification.json_data == %{}
    end

    # Muted user tests

    test "muted user does not receive notifications", %{
      author: author,
      follower: follower
    } do
      {:ok, _} = NotificationMutedUser.mute(follower.id, author.id)

      {:ok, _watchlist} =
        UserList.create_user_list(author, %{name: "Muted Watchlist", is_public: true})

      :timer.sleep(100)

      notifications = AppNotifications.list_notifications_for_user(follower.id)
      assert notifications == []
    end

    test "unmuted user resumes receiving notifications", %{
      author: author,
      follower: follower
    } do
      {:ok, _} = NotificationMutedUser.mute(follower.id, author.id)

      {:ok, _watchlist} =
        UserList.create_user_list(author, %{name: "While Muted", is_public: true})

      :timer.sleep(100)
      assert AppNotifications.list_notifications_for_user(follower.id) == []

      {:ok, _} = NotificationMutedUser.unmute(follower.id, author.id)

      {:ok, _watchlist2} =
        UserList.create_user_list(author, %{name: "After Unmute", is_public: true})

      :timer.sleep(100)

      notifications = AppNotifications.list_notifications_for_user(follower.id)
      assert length(notifications) == 1
      assert hd(notifications).entity_name == "After Unmute"
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

    # follow_user tests

    test "follow_user creates notification for the followed user" do
      user = insert(:user)
      follower = insert(:user)

      assert AppNotifications.list_notifications_for_user(user.id) == []

      {:ok, _} = UserFollower.follow(user.id, follower.id)

      :timer.sleep(100)

      notifications = AppNotifications.list_notifications_for_user(user.id)
      assert length(notifications) == 1

      [notification] = notifications
      assert notification.type == "new_follower"
      assert notification.entity_type == "user"
      assert notification.entity_id == user.id
      assert notification.user_id == follower.id
    end

    test "follow_user does not create notification for the follower" do
      user = insert(:user)
      follower = insert(:user)

      {:ok, _} = UserFollower.follow(user.id, follower.id)

      :timer.sleep(100)

      # The follower should not receive a notification about their own action
      assert AppNotifications.list_notifications_for_user(follower.id) == []
    end
  end

  describe "mark_all_as_read/1" do
    test "marks all unread notifications as read" do
      user = insert(:user)
      author = insert(:user)

      for i <- 1..3 do
        {:ok, notification} =
          AppNotifications.create_notification(%{
            type: "create_watchlist",
            user_id: author.id,
            entity_type: "watchlist",
            entity_id: i
          })

        {:ok, _} =
          AppNotifications.create_notification_read_status(%{
            notification_id: notification.id,
            user_id: user.id
          })
      end

      # All 3 should be unread
      stats = AppNotifications.get_notifications_stats(user.id)
      assert [%{type: "create_watchlist", unread_count: 3}] = stats

      assert {:ok, 3} = AppNotifications.mark_all_as_read(user.id)

      # All should be read now
      stats = AppNotifications.get_notifications_stats(user.id)
      assert [%{type: "create_watchlist", unread_count: 0}] = stats
    end

    test "does not affect already-read notifications" do
      user = insert(:user)
      author = insert(:user)

      {:ok, notification} =
        AppNotifications.create_notification(%{
          type: "create_watchlist",
          user_id: author.id,
          entity_type: "watchlist",
          entity_id: 1
        })

      {:ok, _} =
        AppNotifications.create_notification_read_status(%{
          notification_id: notification.id,
          user_id: user.id
        })

      AppNotifications.set_read_status(user.id, notification.id, true)

      {:ok, read_notif} = AppNotifications.get_notification_for_user(user.id, notification.id)
      original_read_at = read_notif.read_at

      :timer.sleep(100)

      # mark_all_as_read should not change already-read notifications
      assert {:ok, 0} = AppNotifications.mark_all_as_read(user.id)

      {:ok, still_read} = AppNotifications.get_notification_for_user(user.id, notification.id)
      assert still_read.read_at == original_read_at
    end

    test "returns zero when user has no unread notifications" do
      user = insert(:user)
      assert {:ok, 0} = AppNotifications.mark_all_as_read(user.id)
    end
  end

  describe "create_broadcast_notification/1" do
    test "creates notification and read statuses for all registered users" do
      user1 = insert(:user)
      user2 = insert(:user)
      _unregistered = insert(:user_registration_not_finished)

      attrs = %{
        type: "system_notification",
        title: "Maintenance Notice",
        content: "We will be performing maintenance."
      }

      assert {:ok, %{notification: notification, recipients_count: count}} =
               AppNotifications.create_broadcast_notification(attrs)

      assert notification.is_broadcast == true
      assert notification.is_system_generated == true
      assert notification.title == "Maintenance Notice"
      assert count == 2

      # Both registered users should have the notification
      notifications1 = AppNotifications.list_notifications_for_user(user1.id)
      notifications2 = AppNotifications.list_notifications_for_user(user2.id)

      assert length(notifications1) == 1
      assert length(notifications2) == 1

      assert hd(notifications1).type == "system_notification"
      assert hd(notifications1).is_broadcast == true
    end
  end
end
