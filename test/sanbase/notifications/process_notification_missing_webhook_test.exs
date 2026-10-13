defmodule Sanbase.Notifications.ProcessNotificationMissingWebhookTest do
  # Req.new/2 raised on a nil Discord webhook
  use Sanbase.DataCase, async: false

  import Mox
  import Sanbase.NotificationsFixtures

  alias Sanbase.Notifications.{DiscordClient, Notification, Workers.ProcessNotification}

  setup :verify_on_exit!

  setup do
    create_default_templates()
    :ok
  end

  test "DiscordClient.send_message/3 returns an error instead of raising when the webhook is nil" do
    assert {:error, _} = DiscordClient.send_message(nil, "content", [])
  end

  test "a discord notification is cancelled, not retried, when the webhook is not configured" do
    assert nil == Sanbase.Utils.Config.module_get(Sanbase.Notifications, :discord_webhook)

    stub(Sanbase.Notifications.MockDiscordClient, :send_message, &DiscordClient.send_message/3)

    template = Sanbase.Notifications.get_template("metric_created", "all", "discord")

    {:ok, notification} =
      Notification.create(%{
        action: "metric_created",
        params: %{metrics_list: ["unique_social_volume_farcaster_1h"]},
        channel: "discord",
        step: "all",
        status: "available",
        is_manual: false,
        notification_template_id: template.id
      })

    job_args = %{
      "notification_id" => notification.id,
      "action" => notification.action,
      "params" => notification.params,
      "channel" => notification.channel,
      "step" => notification.step,
      "template_id" => notification.notification_template_id
    }

    assert {:cancel, _reason} = ProcessNotification.perform(%Oban.Job{args: job_args})
  end

  test "a manual discord notification returns other send errors so the job is retried" do
    stub(Sanbase.Notifications.MockDiscordClient, :send_message, fn _webhook, _content, _opts ->
      {:error, :rate_limited}
    end)

    template = Sanbase.Notifications.get_template("metric_created", "all", "discord")

    {:ok, notification} =
      Notification.create(%{
        action: "metric_created",
        params: %{metrics_list: ["unique_social_volume_farcaster_1h"]},
        channel: "discord",
        step: "all",
        status: "available",
        is_manual: true,
        notification_template_id: template.id
      })

    job_args = %{
      "is_manual" => true,
      "channel" => "discord",
      "notification_id" => notification.id,
      "params" => %{"content" => "content", "discord_channel" => "metric_updates"}
    }

    assert {:error, :rate_limited} = ProcessNotification.perform(%Oban.Job{args: job_args})
  end
end
