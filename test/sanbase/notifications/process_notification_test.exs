defmodule Sanbase.Notifications.ProcessNotificationTest do
  use Sanbase.DataCase, async: false

  import Mox
  import Sanbase.NotificationsFixtures

  alias Sanbase.Notifications.Notification
  alias Sanbase.Notifications.Workers.ProcessNotification

  setup do
    # Set up any necessary mocks or test data
    Application.put_env(:sanbase, :mailjet_mocked, true)
    on_exit(fn -> Application.put_env(:sanbase, :mailjet_mocked, false) end)
    create_default_templates()
    :ok
  end

  test "processes discord notification job" do
    # Stub the Discord client to simulate sending a message
    stub(Sanbase.Notifications.MockDiscordClient, :send_message, fn _webhook, content, _opts ->
      assert content =~ "metric A"
      :ok
    end)

    notification_template = Sanbase.Notifications.get_template("metric_created", "all", "discord")

    {:ok, notification} =
      Notification.create(%{
        action: "metric_created",
        params: %{metrics_list: ["metric A"]},
        channel: "discord",
        step: "all",
        status: "available",
        is_manual: false,
        notification_template_id: notification_template.id
      })

    job_args = %{
      "notification_id" => notification.id,
      "action" => notification.action,
      "params" => notification.params,
      "channel" => notification.channel,
      "step" => notification.step,
      "template_id" => notification.notification_template_id
    }

    assert {:ok, _notification} = ProcessNotification.perform(%Oban.Job{args: job_args})

    updated_notification = Notification.by_id(notification.id)
    assert updated_notification.status == "completed"
  end

  test "processes email notification job" do
    # Stub the Mailjet client to simulate sending an email
    stub(Sanbase.Email.MockMailjetApi, :send_to_list, fn _list, _subject, content, _opts ->
      assert content =~ "metric A"
      :ok
    end)

    notification_template = Sanbase.Notifications.get_template("metric_created", "all", "email")

    {:ok, notification} =
      Notification.create(%{
        action: "metric_created",
        params: %{metrics_list: ["metric A"]},
        channel: "email",
        step: "all",
        status: "available",
        is_manual: false,
        notification_template_id: notification_template.id
      })

    job_args = %{
      "notification_ids" => [notification.id],
      "action" => notification.action,
      "params" => notification.params,
      "channel" => notification.channel,
      "step" => notification.step,
      "template_id" => notification.notification_template_id
    }

    assert :ok = ProcessNotification.perform(%Oban.Job{args: job_args})

    updated_notification = Notification.by_id(notification.id)
    assert updated_notification.status == "completed"
  end
end
