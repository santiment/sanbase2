defmodule Sanbase.NotificationsTest do
  use Sanbase.DataCase

  alias Sanbase.Notifications

  describe "notification_actions" do
    alias Sanbase.Notifications.NotificationAction

    import Sanbase.NotificationsFixtures

    @invalid_attrs %{
      status: nil,
      action_type: nil,
      scheduled_at: nil,
      requires_verification: nil,
      verified: nil
    }

    test "list_notification_actions/0 returns all notification_actions" do
      notification_action = notification_action_fixture()
      assert Notifications.list_notification_actions() == [notification_action]
    end

    test "get_notification_action!/1 returns the notification_action with given id" do
      notification_action = notification_action_fixture()
      assert Notifications.get_notification_action!(notification_action.id) == notification_action
    end

    test "create_notification_action/1 with valid data creates a notification_action" do
      valid_attrs = %{
        status: "some status",
        action_type: "some action_type",
        scheduled_at: ~U[2024-10-17 07:36:00Z],
        requires_verification: true,
        verified: true
      }

      assert {:ok, %NotificationAction{} = notification_action} =
               Notifications.create_notification_action(valid_attrs)

      assert notification_action.status == "some status"
      assert notification_action.action_type == "some action_type"
      assert notification_action.scheduled_at == ~U[2024-10-17 07:36:00Z]
      assert notification_action.requires_verification == true
      assert notification_action.verified == true
    end

    test "create_notification_action/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               Notifications.create_notification_action(@invalid_attrs)
    end

    test "update_notification_action/2 with valid data updates the notification_action" do
      notification_action = notification_action_fixture()

      update_attrs = %{
        status: "some updated status",
        action_type: "some updated action_type",
        scheduled_at: ~U[2024-10-18 07:36:00Z],
        requires_verification: false,
        verified: false
      }

      assert {:ok, %NotificationAction{} = notification_action} =
               Notifications.update_notification_action(notification_action, update_attrs)

      assert notification_action.status == "some updated status"
      assert notification_action.action_type == "some updated action_type"
      assert notification_action.scheduled_at == ~U[2024-10-18 07:36:00Z]
      assert notification_action.requires_verification == false
      assert notification_action.verified == false
    end

    test "update_notification_action/2 with invalid data returns error changeset" do
      notification_action = notification_action_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Notifications.update_notification_action(notification_action, @invalid_attrs)

      assert notification_action == Notifications.get_notification_action!(notification_action.id)
    end

    test "delete_notification_action/1 deletes the notification_action" do
      notification_action = notification_action_fixture()

      assert {:ok, %NotificationAction{}} =
               Notifications.delete_notification_action(notification_action)

      assert_raise Ecto.NoResultsError, fn ->
        Notifications.get_notification_action!(notification_action.id)
      end
    end

    test "change_notification_action/1 returns a notification_action changeset" do
      notification_action = notification_action_fixture()
      assert %Ecto.Changeset{} = Notifications.change_notification_action(notification_action)
    end
  end

  describe "notification_actions" do
    alias Sanbase.Notifications.NotificationAction

    import Sanbase.NotificationsFixtures

    @invalid_attrs %{
      status: nil,
      action_type: nil,
      scheduled_at: nil,
      requires_verification: nil,
      verified: nil
    }

    test "list_notification_actions/0 returns all notification_actions" do
      notification_action = notification_action_fixture()
      assert Notifications.list_notification_actions() == [notification_action]
    end

    test "get_notification_action!/1 returns the notification_action with given id" do
      notification_action = notification_action_fixture()
      assert Notifications.get_notification_action!(notification_action.id) == notification_action
    end

    test "create_notification_action/1 with valid data creates a notification_action" do
      valid_attrs = %{
        status: "some status",
        action_type: "some action_type",
        scheduled_at: ~U[2024-10-17 07:48:00Z],
        requires_verification: true,
        verified: true
      }

      assert {:ok, %NotificationAction{} = notification_action} =
               Notifications.create_notification_action(valid_attrs)

      assert notification_action.status == "some status"
      assert notification_action.action_type == "some action_type"
      assert notification_action.scheduled_at == ~U[2024-10-17 07:48:00Z]
      assert notification_action.requires_verification == true
      assert notification_action.verified == true
    end

    test "create_notification_action/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               Notifications.create_notification_action(@invalid_attrs)
    end

    test "update_notification_action/2 with valid data updates the notification_action" do
      notification_action = notification_action_fixture()

      update_attrs = %{
        status: "some updated status",
        action_type: "some updated action_type",
        scheduled_at: ~U[2024-10-18 07:48:00Z],
        requires_verification: false,
        verified: false
      }

      assert {:ok, %NotificationAction{} = notification_action} =
               Notifications.update_notification_action(notification_action, update_attrs)

      assert notification_action.status == "some updated status"
      assert notification_action.action_type == "some updated action_type"
      assert notification_action.scheduled_at == ~U[2024-10-18 07:48:00Z]
      assert notification_action.requires_verification == false
      assert notification_action.verified == false
    end

    test "update_notification_action/2 with invalid data returns error changeset" do
      notification_action = notification_action_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Notifications.update_notification_action(notification_action, @invalid_attrs)

      assert notification_action == Notifications.get_notification_action!(notification_action.id)
    end

    test "delete_notification_action/1 deletes the notification_action" do
      notification_action = notification_action_fixture()

      assert {:ok, %NotificationAction{}} =
               Notifications.delete_notification_action(notification_action)

      assert_raise Ecto.NoResultsError, fn ->
        Notifications.get_notification_action!(notification_action.id)
      end
    end

    test "change_notification_action/1 returns a notification_action changeset" do
      notification_action = notification_action_fixture()
      assert %Ecto.Changeset{} = Notifications.change_notification_action(notification_action)
    end
  end

  describe "notifications" do
    alias Sanbase.Notifications.Notification

    import Sanbase.NotificationsFixtures

    @invalid_attrs %{
      status: nil,
      step: nil,
      channels: nil,
      scheduled_at: nil,
      sent_at: nil,
      content: nil,
      display_in_ui: nil,
      template_params: nil
    }

    test "list_notifications/0 returns all notifications" do
      notification = notification_fixture()
      assert Notifications.list_notifications() == [notification]
    end

    test "get_notification!/1 returns the notification with given id" do
      notification = notification_fixture()
      assert Notifications.get_notification!(notification.id) == notification
    end

    test "create_notification/1 with valid data creates a notification" do
      valid_attrs = %{
        status: "some status",
        step: "some step",
        channels: ["option1", "option2"],
        scheduled_at: ~U[2024-10-17 07:56:00Z],
        sent_at: ~U[2024-10-17 07:56:00Z],
        content: "some content",
        display_in_ui: true,
        template_params: %{}
      }

      assert {:ok, %Notification{} = notification} =
               Notifications.create_notification(valid_attrs)

      assert notification.status == "some status"
      assert notification.step == "some step"
      assert notification.channels == ["option1", "option2"]
      assert notification.scheduled_at == ~U[2024-10-17 07:56:00Z]
      assert notification.sent_at == ~U[2024-10-17 07:56:00Z]
      assert notification.content == "some content"
      assert notification.display_in_ui == true
      assert notification.template_params == %{}
    end

    test "create_notification/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Notifications.create_notification(@invalid_attrs)
    end

    test "update_notification/2 with valid data updates the notification" do
      notification = notification_fixture()

      update_attrs = %{
        status: "some updated status",
        step: "some updated step",
        channels: ["option1"],
        scheduled_at: ~U[2024-10-18 07:56:00Z],
        sent_at: ~U[2024-10-18 07:56:00Z],
        content: "some updated content",
        display_in_ui: false,
        template_params: %{}
      }

      assert {:ok, %Notification{} = notification} =
               Notifications.update_notification(notification, update_attrs)

      assert notification.status == "some updated status"
      assert notification.step == "some updated step"
      assert notification.channels == ["option1"]
      assert notification.scheduled_at == ~U[2024-10-18 07:56:00Z]
      assert notification.sent_at == ~U[2024-10-18 07:56:00Z]
      assert notification.content == "some updated content"
      assert notification.display_in_ui == false
      assert notification.template_params == %{}
    end

    test "update_notification/2 with invalid data returns error changeset" do
      notification = notification_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Notifications.update_notification(notification, @invalid_attrs)

      assert notification == Notifications.get_notification!(notification.id)
    end

    test "delete_notification/1 deletes the notification" do
      notification = notification_fixture()
      assert {:ok, %Notification{}} = Notifications.delete_notification(notification)
      assert_raise Ecto.NoResultsError, fn -> Notifications.get_notification!(notification.id) end
    end

    test "change_notification/1 returns a notification changeset" do
      notification = notification_fixture()
      assert %Ecto.Changeset{} = Notifications.change_notification(notification)
    end
  end
end
