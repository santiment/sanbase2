defmodule Sanbase.Notifications.NotificationActionsTest do
  use Sanbase.DataCase, async: false
  import Sanbase.NotificationsFixtures
  import Mox

  alias Sanbase.Notifications.{Handler, EmailNotifier}
  alias Sanbase.Notifications.Notification
  alias Sanbase.Repo

  setup do
    create_default_templates()
    :ok
  end

  describe "metric_created notification" do
    test "creates notification and sends to discord" do
      # Allow the mock to be called multiple times
      stub(Sanbase.Notifications.MockDiscordClient, :send_message, fn _webhook, content, _opts ->
        assert content =~ "metric A"
        assert content =~ "metric B"
        assert content =~ "For more information, please visit #changelog"
        :ok
      end)

      params = %{metrics_list: ["metric A", "metric B"]}

      assert {:ok, notification} =
               Handler.handle_notification(%{
                 action: "metric_created",
                 params: params
               })

      # Add delay to wait for async task
      Process.sleep(100)

      # Verify notification was created correctly
      assert notification.action == "metric_created"
      assert notification.params == params
      assert notification.step == "all"
      assert notification.channels == ["discord", "email"]
    end

    test "marks discord channel as processed after successful sending" do
      # Change expect to stub to allow multiple calls
      stub(Sanbase.Notifications.MockDiscordClient, :send_message, fn _webhook, content, _opts ->
        assert content =~ "metric A"
        :ok
      end)

      {:ok, notification} =
        Handler.handle_notification(%{
          action: "metric_created",
          params: %{metrics_list: ["metric A"]}
        })

      # Wait for async task to complete
      Process.sleep(100)

      # Reload notification from DB
      updated_notification = Notification.by_id(notification.id)
      assert updated_notification.processed_for_discord == true
      assert not is_nil(updated_notification.processed_for_discord_at)
    end
  end

  describe "metric_created email notifications" do
    test "sends daily digest email for new metrics" do
      stub(Sanbase.Notifications.MockDiscordClient, :send_message, fn _webhook, _content, _opts ->
        :ok
      end)

      Sanbase.Email.MockMailjetApi
      |> expect(:list_subscribed_emails, fn :metric_updates_dev -> {:ok, ["test@example.com"]} end)
      |> expect(:send_to_list, fn :metric_updates_dev, "Sanbase Metric Updates", content, _opts ->
        assert content =~ "metric A"
        assert content =~ "metric B"
        :ok
      end)

      # Create notifications
      {:ok, _notification1} =
        Handler.handle_notification(%{
          action: "metric_created",
          params: %{metrics_list: ["metric A"]}
        })

      {:ok, _notification2} =
        Handler.handle_notification(%{
          action: "metric_created",
          params: %{metrics_list: ["metric B"]}
        })

      # Trigger daily digest
      EmailNotifier.send_daily_digest("metric_created")

      # Verify notifications were marked as processed
      notifications = Repo.all(Notification)
      assert Enum.all?(notifications, & &1.processed_for_email)
      assert Enum.all?(notifications, &(not is_nil(&1.processed_for_email_at)))
    end

    test "handles email sending failure" do
      stub(Sanbase.Notifications.MockDiscordClient, :send_message, fn _webhook, _content, _opts ->
        :ok
      end)

      Sanbase.Email.MockMailjetApi
      |> expect(:list_subscribed_emails, fn :metric_updates_dev -> {:ok, ["test@example.com"]} end)
      |> expect(:send_to_list, fn :metric_updates_dev, "Sanbase Metric Updates", content, _opts ->
        assert content =~ "metric A"
        {:error, "Failed to send email"}
      end)

      # Create a notification
      {:ok, notification} =
        Handler.handle_notification(%{
          action: "metric_created",
          params: %{metrics_list: ["metric A"]}
        })

      # Trigger daily digest
      EmailNotifier.send_daily_digest("metric_created")

      # Verify notification wasn't marked as processed
      updated_notification = Repo.get(Notification, notification.id)
      refute updated_notification.processed_for_email
      assert is_nil(updated_notification.processed_for_email_at)
    end
  end

  describe "metric_deleted notification" do
    test "creates notifications and sends immediate discord message" do
      # Change expect to stub to allow multiple calls
      stub(Sanbase.Notifications.MockDiscordClient, :send_message, fn _webhook, content, _opts ->
        assert content =~ "metric A"
        assert content =~ "metric B"
        :ok
      end)

      scheduled_at = ~U[2024-11-29 12:00:00Z]
      params = %{metrics_list: ["metric A", "metric B"], scheduled_at: scheduled_at}

      assert {:ok, notification} =
               Handler.handle_notification(%{
                 action: "metric_deleted",
                 params: params
               })

      # Add delay to wait for async task
      Process.sleep(100)

      # Verify immediate notification was created correctly
      assert notification.action == "metric_deleted"
      assert notification.params == params
      assert notification.step == "before"
      assert notification.channels == ["discord", "email"]

      # Verify scheduled jobs were created
      jobs = Oban.Job |> Repo.all()
      assert length(jobs) == 2

      # Verify reminder job (3 days before)
      reminder_job = Enum.find(jobs, &(&1.args["step"] == "reminder"))
      assert reminder_job.args["action"] == "metric_deleted"

      assert DateTime.truncate(reminder_job.scheduled_at, :second) ==
               DateTime.add(scheduled_at, -3, :day)

      # Verify after job
      after_job = Enum.find(jobs, &(&1.args["step"] == "after"))
      assert after_job.args["action"] == "metric_deleted"
      assert DateTime.truncate(after_job.scheduled_at, :second) == scheduled_at
    end

    test "sends daily digest email for deleted metrics" do
      # Change expect to stub to allow multiple calls
      stub(Sanbase.Notifications.MockDiscordClient, :send_message, fn _webhook, _content, _opts ->
        :ok
      end)

      Sanbase.Email.MockMailjetApi
      |> expect(:list_subscribed_emails, fn :metric_updates_dev -> {:ok, ["test@example.com"]} end)
      |> expect(:send_to_list, fn :metric_updates_dev, "Sanbase Metric Updates", content, _opts ->
        assert content =~ "metric A"
        assert content =~ "metric B"
        :ok
      end)

      scheduled_at = ~U[2024-11-29 12:00:00Z]

      # Create notifications with same scheduled_at
      {:ok, _notification1} =
        Handler.handle_notification(%{
          action: "metric_deleted",
          params: %{metrics_list: ["metric A"], scheduled_at: scheduled_at}
        })

      {:ok, _notification2} =
        Handler.handle_notification(%{
          action: "metric_deleted",
          params: %{metrics_list: ["metric B"], scheduled_at: scheduled_at}
        })

      # Trigger daily digest
      EmailNotifier.send_daily_digest("metric_deleted")

      # Verify notifications were marked as processed
      notifications = Repo.all(Notification)
      assert Enum.all?(notifications, & &1.processed_for_email)
      assert Enum.all?(notifications, &(not is_nil(&1.processed_for_email_at)))
    end
  end

  describe "manual notification" do
    test "sends notifications to specified channels" do
      stub(Sanbase.Notifications.MockDiscordClient, :send_message, fn _webhook, content, _opts ->
        assert content == "Discord message"
        :ok
      end)

      Sanbase.Email.MockMailjetApi
      |> expect(:send_to_list, fn :metric_updates_dev, subject, content, _opts ->
        assert subject == "Test Subject"
        assert content == "Email message"
        :ok
      end)

      params = %{
        discord_text: "Discord message",
        email_text: "Email message",
        email_subject: "Test Subject"
      }

      assert {:ok, notification} =
               Handler.handle_notification(%{
                 action: "manual",
                 params: params
               })

      Process.sleep(100)

      # Verify notification was created correctly
      assert notification.action == "manual"
      assert notification.params == params
      assert notification.step == "all"
      assert Enum.sort(notification.channels) == ["discord", "email"]

      # Verify channels were marked as processed
      updated_notification = Notification.by_id(notification.id)
      assert updated_notification.processed_for_discord
      assert updated_notification.processed_for_email
    end

    test "only sends to channels with content" do
      stub(Sanbase.Notifications.MockDiscordClient, :send_message, fn _webhook, content, _opts ->
        assert content == "Discord only"
        :ok
      end)

      params = %{
        discord_text: "Discord only",
        email_text: "",
        email_subject: "Test Subject"
      }

      assert {:ok, notification} =
               Handler.handle_notification(%{
                 action: "manual",
                 params: params
               })

      Process.sleep(100)

      assert notification.channels == ["discord"]
      refute notification.processed_for_email
    end
  end

  describe "alert notification" do
    test "sends detected alert to discord" do
      stub(Sanbase.Notifications.MockDiscordClient, :send_message, fn _webhook, content, _opts ->
        assert content =~ "Metric XYZ"
        assert content =~ "Category A"
        assert content =~ "Category B"
        :ok
      end)

      params = %{
        metric_name: "Metric XYZ",
        asset_categories: ["Category A", "Category B"]
      }

      assert {:ok, notification} =
               Handler.handle_notification(%{
                 action: "alert",
                 params: params,
                 step: "detected"
               })

      Process.sleep(100)

      assert notification.action == "alert"
      assert notification.params == params
      assert notification.step == "detected"
      assert notification.channels == ["discord"]

      updated_notification = Notification.by_id(notification.id)
      assert updated_notification.processed_for_discord
    end

    test "sends resolved alert to discord" do
      # Change expect to stub to allow multiple calls
      stub(Sanbase.Notifications.MockDiscordClient, :send_message, fn _webhook, content, _opts ->
        assert content =~ "Metric XYZ"
        assert content =~ "resolved"
        :ok
      end)

      params = %{
        metric_name: "Metric XYZ",
        asset_categories: ["Category A"]
      }

      assert {:ok, notification} =
               Handler.handle_notification(%{
                 action: "alert",
                 params: params,
                 step: "resolved"
               })

      Process.sleep(100)

      assert notification.step == "resolved"
      assert notification.channels == ["discord"]

      updated_notification = Notification.by_id(notification.id)
      assert updated_notification.processed_for_discord
    end
  end
end
