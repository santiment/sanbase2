defmodule Sanbase.Notifications.ActionsTest do
  use Sanbase.DataCase, async: false
  import Mox
  import Sanbase.NotificationsFixtures
  alias Sanbase.Notifications

  setup :verify_on_exit!

  setup do
    # Create all required templates before each test
    create_default_templates()
    :ok
  end

  test "sends create notification once on Discord" do
    metrics_list = ["Metric A", "Metric B"]

    {:ok, notification_action} =
      Notifications.create_notification_action(%{
        action_type: :create,
        scheduled_at: DateTime.utc_now(),
        status: :pending,
        requires_verification: false,
        verified: true
      })

    {:ok, notification} =
      Notifications.create_notification(%{
        notification_action_id: notification_action.id,
        step: :once,
        status: :pending,
        scheduled_at: DateTime.utc_now(),
        channels: [:discord],
        display_in_ui: false,
        content: "---",
        template_params: %{
          "metrics_list" => metrics_list
        }
      })

    content = Sanbase.Notifications.TemplateRenderer.render_content(notification)
    {:ok, notification} = Notifications.update_notification(notification, %{content: content})

    # Set up Mox expectation
    Sanbase.Notifications.MockDiscordClient
    |> expect(:send_message, fn _webhook, message, _opts ->
      expected_content = """
      In the latest update the following metrics have been added:
      Metric A, Metric B
      For more information, please visit #changelog
      """

      assert String.trim(message) == String.trim(expected_content)
      :ok
    end)

    Sanbase.Notifications.Sender.send_notification(notification)

    notification = Notifications.get_notification!(notification.id)
    assert notification.status == :completed
  end

  test "sends update notifications before and after on Discord" do
    metrics_list = ["Metric X", "Metric Y"]

    {:ok, notification_action} =
      Notifications.create_notification_action(%{
        action_type: :update,
        scheduled_at: DateTime.utc_now(),
        status: :pending,
        requires_verification: false,
        verified: true
      })

    scheduled_at_str = "October 22, 2024, 10:00 AM UTC"
    duration_str = "3 hours"

    {:ok, before_notification} =
      Notifications.create_notification(%{
        notification_action_id: notification_action.id,
        step: :before,
        scheduled_at: DateTime.utc_now(),
        channels: [:discord],
        content: "---",
        template_params: %{
          "scheduled_at" => scheduled_at_str,
          "duration" => duration_str,
          "metrics_list" => metrics_list
        }
      })

    {:ok, after_notification} =
      Notifications.create_notification(%{
        notification_action_id: notification_action.id,
        step: :after,
        # 4 hours later
        scheduled_at: DateTime.add(DateTime.utc_now(), 3600 * 4, :second),
        channels: [:discord],
        content: "---",
        template_params: %{
          "metrics_list" => metrics_list
        }
      })

    before_content =
      before_notification
      |> Map.put(:notification_action, notification_action)
      |> Sanbase.Notifications.TemplateRenderer.render_content()

    {:ok, before_notification} =
      Notifications.update_notification(before_notification, %{content: before_content})

    after_content =
      after_notification
      |> Map.put(:notification_action, notification_action)
      |> Sanbase.Notifications.TemplateRenderer.render_content()

    {:ok, after_notification} =
      Notifications.update_notification(after_notification, %{content: after_content})

    Sanbase.Notifications.MockDiscordClient
    |> expect(:send_message, 2, fn _webhook, message, _opts ->
      if String.contains?(message, "In order to make our data more precise") do
        expected_before_content = """
        In order to make our data more precise, we're going to run a recalculation of the following metrics:
        Metric X, Metric Y
        This will be done on #{scheduled_at_str} and will take approximately #{duration_str}
        """

        assert String.trim(message) == String.trim(expected_before_content)
      else
        expected_after_content = """
        Recalculation of the following metrics has been completed successfully:
        Metric X, Metric Y
        """

        assert String.trim(message) == String.trim(expected_after_content)
      end

      :ok
    end)

    Sanbase.Notifications.Sender.send_notification(before_notification)
    Sanbase.Notifications.Sender.send_notification(after_notification)
  end

  test "sends delete notifications three times via Discord and email" do
    metrics_list = ["Metric A", "Metric B"]
    scheduled_at_str = "November 30, 2024, 10:00 AM UTC"

    {:ok, notification_action} =
      Notifications.create_notification_action(%{
        action_type: :delete,
        scheduled_at: DateTime.utc_now(),
        status: :pending,
        requires_verification: false,
        verified: true
      })

    notifications =
      for step <- [:before, :reminder, :after] do
        {:ok, notification} =
          Notifications.create_notification(%{
            notification_action_id: notification_action.id,
            step: step,
            scheduled_at: get_scheduled_at(step),
            channels: [:discord, :email],
            content: "---",
            template_params: %{
              "scheduled_at" => scheduled_at_str,
              "metrics_list" => metrics_list
            }
          })

        notification
      end

    notifications =
      Enum.map(notifications, fn notif ->
        content = Sanbase.Notifications.TemplateRenderer.render_content(notif)
        {:ok, updated_notif} = Notifications.update_notification(notif, %{content: content})
        updated_notif
      end)

    Sanbase.Notifications.MockDiscordClient
    |> expect(:send_message, 3, fn _webhook, message, _opts ->
      assert_discord_message(message, scheduled_at_str)
      :ok
    end)

    Sanbase.Notifications.MockEmailClient
    |> expect(:send_email, 3, fn _to, subject, body ->
      assert subject == "Metric Deprecation Notice"
      assert_email_body(body, scheduled_at_str)
      :ok
    end)

    Enum.each(notifications, &Sanbase.Notifications.Sender.send_notification/1)

    Enum.each(notifications, fn notification ->
      updated_notification = Notifications.get_notification!(notification.id)
      assert updated_notification.status == :completed
    end)
  end

  test "sends alert notifications on Discord when detected and resolved" do
    metric_name = "Metric XYZ"
    asset_categories = ["Category A", "Category B"]

    {:ok, notification_action} =
      Notifications.create_notification_action(%{
        action_type: :alert,
        scheduled_at: DateTime.utc_now(),
        status: :pending,
        requires_verification: false,
        verified: true
      })

    {:ok, detected_notification} =
      Notifications.create_notification(%{
        notification_action_id: notification_action.id,
        step: :detected,
        scheduled_at: DateTime.utc_now(),
        channels: [:discord],
        content: "---",
        template_params: %{
          "metric_name" => metric_name,
          "asset_categories" => asset_categories
        }
      })

    {:ok, resolved_notification} =
      Notifications.create_notification(%{
        notification_action_id: notification_action.id,
        step: :resolved,
        # 2 hours later
        scheduled_at: DateTime.add(DateTime.utc_now(), 3600 * 2, :second),
        channels: [:discord],
        content: "---",
        template_params: %{
          "metric_name" => metric_name
        }
      })

    detected_content =
      detected_notification
      |> Map.put(:notification_action, notification_action)
      |> Sanbase.Notifications.TemplateRenderer.render_content()

    {:ok, detected_notification} =
      Notifications.update_notification(detected_notification, %{content: detected_content})

    resolved_content =
      resolved_notification
      |> Map.put(:notification_action, notification_action)
      |> Sanbase.Notifications.TemplateRenderer.render_content()

    {:ok, resolved_notification} =
      Notifications.update_notification(resolved_notification, %{content: resolved_content})

    Sanbase.Notifications.MockDiscordClient
    |> expect(:send_message, 2, fn _webhook, message, _opts ->
      if String.contains?(message, "Metric delay alert") do
        expected_content = """
        Metric delay alert: #{metric_name} is experiencing a delay due to technical issues. Affected assets: #{Enum.join(asset_categories, ", ")}
        """

        assert String.trim(message) == String.trim(expected_content)
      else
        expected_content = """
        Metric delay resolved: #{metric_name} is back to normal
        """

        assert String.trim(message) == String.trim(expected_content)
      end

      :ok
    end)

    Sanbase.Notifications.Sender.send_notification(detected_notification)

    Sanbase.Notifications.Sender.send_notification(resolved_notification)
  end

  test "sends manual notification with custom text on Discord" do
    custom_text = "Important announcement: System maintenance scheduled for tomorrow"

    {:ok, notification_action} =
      Notifications.create_notification_action(%{
        action_type: :manual,
        scheduled_at: DateTime.utc_now(),
        status: :pending,
        requires_verification: false,
        verified: true
      })

    {:ok, notification} =
      Notifications.create_notification(%{
        notification_action_id: notification_action.id,
        step: :once,
        status: :pending,
        scheduled_at: DateTime.utc_now(),
        channels: [:discord],
        display_in_ui: true,
        content: custom_text
      })

    Sanbase.Notifications.MockDiscordClient
    |> expect(:send_message, fn _webhook, message, _opts ->
      assert String.trim(message) == custom_text
      :ok
    end)

    Sanbase.Notifications.Sender.send_notification(notification)

    notification = Notifications.get_notification!(notification.id)
    assert notification.status == :completed
  end

  defp get_scheduled_at(:before), do: DateTime.utc_now()
  defp get_scheduled_at(:reminder), do: DateTime.add(DateTime.utc_now(), 3600 * 24 * 27, :second)
  defp get_scheduled_at(:after), do: DateTime.add(DateTime.utc_now(), 3600 * 24 * 30, :second)

  defp assert_discord_message(message, scheduled_at_str) do
    cond do
      String.contains?(message, "Due to lack of usage") ->
        assert message =~
                 "Due to lack of usage, we made a decision to deprecate the following metrics:"

        assert message =~ "Metric A, Metric B"
        assert message =~ "This is planned to take place on #{scheduled_at_str}"

      String.contains?(message, "This is a reminder") ->
        assert message =~
                 "This is a reminder about the scheduled deprecation of the following metrics:"

        assert message =~ "Metric A, Metric B"
        assert message =~ "It will happen on #{scheduled_at_str}"

      true ->
        assert message =~ "Deprecation of the following metrics has been completed successfully:"
        assert message =~ "Metric A, Metric B"
    end
  end

  defp assert_email_body(body, scheduled_at_str) do
    cond do
      String.contains?(body, "Due to lack of usage") ->
        assert body =~
                 "Due to lack of usage, we made a decision to deprecate the following metrics:"

        assert body =~ "Metric A, Metric B"
        assert body =~ "This is planned to take place on #{scheduled_at_str}"

      String.contains?(body, "This is a reminder") ->
        assert body =~
                 "This is a reminder about the scheduled deprecation of the following metrics:"

        assert body =~ "Metric A, Metric B"
        assert body =~ "It will happen on #{scheduled_at_str}"

      true ->
        assert body =~ "Deprecation of the following metrics has been completed successfully:"
        assert body =~ "Metric A, Metric B"
    end
  end
end
