defmodule Sanbase.Notifications.NotificationActionsTest do
  use Sanbase.DataCase, async: false
  import Sanbase.NotificationsFixtures
  import Mox

  alias Sanbase.Notifications.{Handler, EmailNotifier}
  alias Sanbase.Notifications.Notification
  alias Sanbase.Repo

  setup do
    Application.put_env(:sanbase, :mailjet_mocked, true)
    on_exit(fn -> Application.put_env(:sanbase, :mailjet_mocked, false) end)
    create_default_templates()
    :ok
  end

  describe "metric_created notification" do
    test "creates notifications for both discord and email channels" do
      # Allow the mock to be called multiple times
      stub(Sanbase.Notifications.MockDiscordClient, :send_message, fn _webhook, content, _opts ->
        assert content =~ "metric A"
        assert content =~ "metric B"
        assert content =~ "For more information, please visit #changelog"
        :ok
      end)

      params = %{metrics_list: ["metric A", "metric B"]}

      notifications =
        Handler.handle_notification(%{
          action: "metric_created",
          params: params
        })

      # Ensure notifications are returned as a list
      assert length(notifications) == 2

      # Find both notifications
      discord_notification = Enum.find(notifications, &(&1.channel == "discord"))
      email_notification = Enum.find(notifications, &(&1.channel == "email"))

      # Verify discord notification
      assert discord_notification.action == "metric_created"
      assert discord_notification.params == params
      assert discord_notification.step == "all"
      assert discord_notification.channel == "discord"
      assert discord_notification.status == "available"
      assert discord_notification.is_manual == false
      assert not is_nil(discord_notification.job_id)
      assert not is_nil(discord_notification.notification_template_id)

      # Verify email notification
      assert email_notification.action == "metric_created"
      assert email_notification.params == params
      assert email_notification.step == "all"
      assert email_notification.channel == "email"
      assert email_notification.status == "available"
      assert email_notification.is_manual == false
      # Email notifications don't get immediate jobs
      assert is_nil(email_notification.job_id)
      assert not is_nil(email_notification.notification_template_id)
    end
  end

  describe "metric_deleted notification" do
    test "creates notifications for both discord and email channels" do
      stub(Sanbase.Notifications.MockDiscordClient, :send_message, fn _webhook, content, _opts ->
        assert content =~ "metric X"
        assert content =~ "scheduled to be deprecated"
        assert content =~ "2024-12-31"
        :ok
      end)

      scheduled_at = ~N[2024-12-31 00:00:00]
      params = %{metrics_list: ["metric X"], scheduled_at: scheduled_at}

      notifications =
        Handler.handle_notification(%{
          action: "metric_deleted",
          params: params,
          step: "before"
        })

      assert length(notifications) == 2

      discord_notification = Enum.find(notifications, &(&1.channel == "discord"))
      email_notification = Enum.find(notifications, &(&1.channel == "email"))

      # Verify discord notification
      assert discord_notification.action == "metric_deleted"
      assert discord_notification.params == params
      assert discord_notification.step == "before"
      assert discord_notification.channel == "discord"
      assert discord_notification.status == "available"
      assert discord_notification.is_manual == false
      assert not is_nil(discord_notification.job_id)
      assert not is_nil(discord_notification.notification_template_id)

      # Verify email notification
      assert email_notification.action == "metric_deleted"
      assert email_notification.params == params
      assert email_notification.step == "before"
      assert email_notification.channel == "email"
      assert email_notification.status == "available"
      assert email_notification.is_manual == false
      assert is_nil(email_notification.job_id)
      assert not is_nil(email_notification.notification_template_id)
    end
  end
end
