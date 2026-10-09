defmodule Sanbase.Notifications.ProcessNotificationMissingWebhookTest do
  @moduledoc ~s"""
  Reproduces SANBASE-BACKEND-PROD-G53:
  ArgumentError: expected 1st argument to be a url, a keyword list, or a request, got: nil
  in Req.new/2, called from DiscordClient.send_message/3.

  The DISCORD_NOTIFICATIONS_WEBHOOK_URL env var is not set, so the webhook is nil.
  The worker raises on every one of its 20 attempts, each one reported to Sentry.
  A missing webhook is a configuration problem that retries cannot fix.
  """
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
    # The webhook comes from DISCORD_NOTIFICATIONS_WEBHOOK_URL which is not set in test
    assert nil ==
             Sanbase.Utils.Config.module_get(Sanbase.Notifications, :discord_webhook)

    # The client must not be invoked with a nil webhook
    stub(Sanbase.Notifications.MockDiscordClient, :send_message, fn
      nil, _content, _opts -> DiscordClient.send_message(nil, "content", [])
      _webhook, _content, _opts -> :ok
    end)

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
end
