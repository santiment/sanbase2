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
      content = notification.content
      email_client().send_email("test@example.com", "Metric Deprecation Notice", content)
    end

    # Update notification status, e.g., to :sent
    Notifications.update_notification(notification, %{
      status: :completed,
      sent_at: DateTime.utc_now()
    })
  end

  def discord_client do
    Application.get_env(:sanbase, :discord_client, DiscordClient)
  end

  def email_client do
    Application.get_env(:sanbase, :email_client, Sanbase.Notifications.EmailClient)
  end
end
