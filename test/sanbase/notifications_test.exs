defmodule Sanbase.NotificationsTest do
  use Sanbase.DataCase

  alias Sanbase.Notifications.NotificationAction
  alias Sanbase.Repo

  describe "notification_actions" do
    import Sanbase.NotificationsFixtures

    @invalid_attrs %{
      status: nil,
      action_type: nil,
      scheduled_at: nil,
      requires_verification: nil,
      verified: nil
    }

    test "list_notification_actions/0 returns all notification_actions" do
      {:ok, notification_action} = notification_action_fixture()
      assert Sanbase.Notifications.list_notification_actions() == [notification_action]
    end

    test "get_notification_action!/1 returns the notification_action with given id" do
      {:ok, notification_action} = notification_action_fixture()

      assert Sanbase.Notifications.get_notification_action!(notification_action.id) ==
               notification_action
    end

    test "create_notification_action/1 with valid data creates a notification_action" do
      valid_attrs = %{
        status: :pending,
        action_type: :create,
        scheduled_at: ~U[2024-10-17 07:48:00Z],
        requires_verification: true,
        verified: true
      }

      assert {:ok, %NotificationAction{} = notification_action} =
               Sanbase.Notifications.create_notification_action(valid_attrs)

      assert notification_action.status == :pending
      assert notification_action.action_type == :create
      assert notification_action.scheduled_at == ~U[2024-10-17 07:48:00Z]
      assert notification_action.requires_verification == true
      assert notification_action.verified == true
    end

    test "create_notification_action/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               Sanbase.Notifications.create_notification_action(@invalid_attrs)
    end

    test "update_notification_action/2 with valid data updates the notification_action" do
      {:ok, notification_action} = notification_action_fixture()

      update_attrs = %{
        status: :completed,
        action_type: :update,
        scheduled_at: ~U[2024-10-18 07:48:00Z],
        requires_verification: false,
        verified: false
      }

      assert {:ok, %NotificationAction{} = notification_action} =
               Sanbase.Notifications.update_notification_action(notification_action, update_attrs)

      assert notification_action.status == :completed
      assert notification_action.action_type == :update
      assert notification_action.scheduled_at == ~U[2024-10-18 07:48:00Z]
      assert notification_action.requires_verification == false
      assert notification_action.verified == false
    end

    test "update_notification_action/2 with invalid data returns error changeset" do
      {:ok, notification_action} = notification_action_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Sanbase.Notifications.update_notification_action(
                 notification_action,
                 @invalid_attrs
               )

      assert notification_action ==
               Sanbase.Notifications.get_notification_action!(notification_action.id)
    end

    test "delete_notification_action/1 deletes the notification_action" do
      {:ok, notification_action} = notification_action_fixture()

      assert {:ok, %NotificationAction{}} =
               Sanbase.Notifications.delete_notification_action(notification_action)

      assert_raise Ecto.NoResultsError, fn ->
        Sanbase.Notifications.get_notification_action!(notification_action.id)
      end
    end

    test "change_notification_action/1 returns a notification_action changeset" do
      {:ok, notification_action} = notification_action_fixture()

      assert %Ecto.Changeset{} =
               Sanbase.Notifications.change_notification_action(notification_action)
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
      {:ok, notification} = notification_fixture()
      # Fetch without preloading to match fixture
      assert Sanbase.Notifications.list_notifications() |> Repo.preload(:notification_action) == [
               notification
             ]
    end

    test "get_notification!/1 returns the notification with given id" do
      {:ok, notification} = notification_fixture()
      # Fetch without preloading to match fixture
      assert Sanbase.Notifications.get_notification!(notification.id)
             |> Repo.preload(:notification_action) == notification
    end

    test "create_notification/1 with valid data creates a notification" do
      # Create a notification action first
      {:ok, notification_action} = notification_action_fixture()

      valid_attrs = %{
        status: :pending,
        # Changed from :create to :once
        step: :once,
        channels: [:discord],
        # Add this
        notification_action_id: notification_action.id,
        scheduled_at: ~U[2024-10-17 07:56:00Z],
        sent_at: ~U[2024-10-17 07:56:00Z],
        content: "some content",
        display_in_ui: true,
        template_params: %{}
      }

      assert {:ok, %Notification{} = notification} =
               Sanbase.Notifications.create_notification(valid_attrs)

      # Add assertions to verify the created notification
      assert notification.status == :pending
      assert notification.step == :once
      assert notification.channels == [:discord]
      assert notification.notification_action_id == notification_action.id
      assert notification.content == "some content"
      assert notification.display_in_ui == true
    end

    test "create_notification/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               Sanbase.Notifications.create_notification(@invalid_attrs)
    end

    test "update_notification/2 with valid data updates the notification" do
      {:ok, notification} = notification_fixture()

      update_attrs = %{
        # Changed from "some updated status"
        status: :completed,
        # Changed from "some updated step"
        step: :reminder,
        # Changed from ["option1"] to use valid channel enum
        channels: [:discord],
        scheduled_at: ~U[2024-10-18 07:56:00Z],
        sent_at: ~U[2024-10-18 07:56:00Z],
        content: "some updated content",
        display_in_ui: false,
        template_params: %{}
      }

      assert {:ok, %Notification{} = notification} =
               Sanbase.Notifications.update_notification(notification, update_attrs)

      assert notification.status == :completed
      assert notification.step == :reminder
      assert notification.channels == [:discord]
      assert notification.scheduled_at == ~U[2024-10-18 07:56:00Z]
      assert notification.sent_at == ~U[2024-10-18 07:56:00Z]
      assert notification.content == "some updated content"
      assert notification.display_in_ui == false
      assert notification.template_params == %{}
    end

    test "update_notification/2 with invalid data returns error changeset" do
      {:ok, notification} = notification_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Sanbase.Notifications.update_notification(notification, @invalid_attrs)

      # Fetch without preloading to match fixture
      fetched_notification =
        Sanbase.Notifications.get_notification!(notification.id)
        |> Repo.preload(:notification_action)

      assert notification == fetched_notification
    end

    test "delete_notification/1 deletes the notification" do
      {:ok, notification} = notification_fixture()
      assert {:ok, %Notification{}} = Sanbase.Notifications.delete_notification(notification)

      assert_raise Ecto.NoResultsError, fn ->
        Sanbase.Notifications.get_notification!(notification.id)
      end
    end

    test "change_notification/1 returns a notification changeset" do
      {:ok, notification} = notification_fixture()
      assert %Ecto.Changeset{} = Sanbase.Notifications.change_notification(notification)
    end
  end

  describe "notification_templates" do
    alias Sanbase.Notifications.NotificationTemplate

    import Sanbase.NotificationsFixtures

    @invalid_attrs %{template: nil, step: nil, channel: nil, action_type: nil}

    test "list_notification_templates/0 returns all notification_templates" do
      notification_template = notification_template_fixture()
      assert Notifications.list_notification_templates() == [notification_template]
    end

    test "get_notification_template!/1 returns the notification_template with given id" do
      notification_template = notification_template_fixture()

      assert Notifications.get_notification_template!(notification_template.id) ==
               notification_template
    end

    test "create_notification_template/1 with valid data creates a notification_template" do
      valid_attrs = %{
        template: "some template",
        step: "some step",
        channel: "some channel",
        action_type: "some action_type"
      }

      assert {:ok, %NotificationTemplate{} = notification_template} =
               Notifications.create_notification_template(valid_attrs)

      assert notification_template.template == "some template"
      assert notification_template.step == "some step"
      assert notification_template.channel == "some channel"
      assert notification_template.action_type == "some action_type"
    end

    test "create_notification_template/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               Notifications.create_notification_template(@invalid_attrs)
    end

    test "update_notification_template/2 with valid data updates the notification_template" do
      notification_template = notification_template_fixture()

      update_attrs = %{
        template: "some updated template",
        step: "some updated step",
        channel: "some updated channel",
        action_type: "some updated action_type"
      }

      assert {:ok, %NotificationTemplate{} = notification_template} =
               Notifications.update_notification_template(notification_template, update_attrs)

      assert notification_template.template == "some updated template"
      assert notification_template.step == "some updated step"
      assert notification_template.channel == "some updated channel"
      assert notification_template.action_type == "some updated action_type"
    end

    test "update_notification_template/2 with invalid data returns error changeset" do
      notification_template = notification_template_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Notifications.update_notification_template(notification_template, @invalid_attrs)

      assert notification_template ==
               Notifications.get_notification_template!(notification_template.id)
    end

    test "delete_notification_template/1 deletes the notification_template" do
      notification_template = notification_template_fixture()

      assert {:ok, %NotificationTemplate{}} =
               Notifications.delete_notification_template(notification_template)

      assert_raise Ecto.NoResultsError, fn ->
        Notifications.get_notification_template!(notification_template.id)
      end
    end

    test "change_notification_template/1 returns a notification_template changeset" do
      notification_template = notification_template_fixture()
      assert %Ecto.Changeset{} = Notifications.change_notification_template(notification_template)
    end
  end
end
