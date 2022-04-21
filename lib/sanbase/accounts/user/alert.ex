defmodule Sanbase.Accounts.User.Alert do
  alias Sanbase.Accounts.UserSettings
  alias Sanbase.Accounts.Settings

  def can_receive_telegram_alert?(user) do
    user = Sanbase.Repo.preload(user, :user_settings)

    settings = UserSettings.settings_for(user)
    limit = Settings.get_alerts_limit_per_day(settings, "telegram")
    fired_today = Settings.get_alerts_fired_today(settings, "telegram")

    alert_receivable? = settings.has_telegram_connected and settings.alert_notify_telegram
    alert_limit_reached? = fired_today >= limit

    alert_receivable? and not alert_limit_reached?
  end

  def can_receive_email_alert?(user) do
    user = Sanbase.Repo.preload(user, :user_settings)

    settings = UserSettings.settings_for(user)

    limit = Settings.get_alerts_limit_per_day(settings, "email")
    fired_today = Settings.get_alerts_fired_today(settings, "email")

    alert_receivable? = is_binary(user.email) and settings.alert_notify_email
    alert_limit_reached? = fired_today >= limit

    alert_receivable? and not alert_limit_reached?
  end
end
