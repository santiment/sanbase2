defmodule Sanbase.Accounts.User.Alert do
  def can_receive_telegram_alert?(user) do
    user = Sanbase.Repo.preload(user, :user_settings)

    settings = Sanbase.Accounts.UserSettings.settings_for(user)

    settings.has_telegram_connected and settings.alert_notify_telegram
  end

  def can_receive_email_alert?(user) do
    user = Sanbase.Repo.preload(user, :user_settings)
    settings = Sanbase.Accounts.UserSettings.settings_for(user)

    is_binary(user.email) and settings.alert_notify_email
  end
end
