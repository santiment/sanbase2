defmodule Sanbase.Notifications.Sender do
  alias Sanbase.Notifications.{DiscordClient, Notification}
  alias Sanbase.Notifications
  alias Sanbase.Utils.Config

  def send_notification(%Notification{} = notification) do
    notification = Sanbase.Repo.preload(notification, [:notification_action])

    if :discord in notification.channels do
      content = notification.content
      webhook = Config.module_get(DiscordClient, :webhook)

      discord_client().send_message(webhook, content, username: "Sanbase")
    end

    if :email in notification.channels do
      # Create email notification with multiple addresses
      Notifications.create_email_notification(%{
        notification_id: notification.id,
        # TODO: get actual addresses from user settings
        to_addresses: ["test@example.com", "other@example.com"],
        subject: "Metric Deprecation Notice",
        content: notification.content
      })
    end

    # Update notification status, e.g., to :sent
    Notifications.update_notification(notification, %{
      status: :completed,
      sent_at: DateTime.utc_now()
    })
  end

  def send_approved_email(%Notifications.EmailNotification{} = email_notification) do
    Sanbase.Email.MailjetApi.send_to_list(
      :metric_updates,
      email_notification.subject,
      email_notification.content
    )

    Notifications.update_email_notification(email_notification, %{sent_at: DateTime.utc_now()})
  end

  def discord_client do
    Application.get_env(:sanbase, :discord_client, DiscordClient)
  end

  def email_client do
    Application.get_env(:sanbase, :email_client, Sanbase.Notifications.EmailClient)
  end
end
