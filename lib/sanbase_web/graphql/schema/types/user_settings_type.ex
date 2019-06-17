defmodule SanbaseWeb.Graphql.UserSettingsTypes do
  use Absinthe.Schema.Notation

  enum :newsletter_subscription_type do
    value(:weekly)
    value(:daily)
    value(:off)
  end

  object :user_settings do
    field(:has_telegram_connected, :boolean)
    field(:signal_notify_telegram, :boolean)
    field(:signal_notify_email, :boolean)
    field(:newsletter_subscription, :newsletter_subscription_type)
  end
end
