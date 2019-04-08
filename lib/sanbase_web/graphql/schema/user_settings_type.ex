defmodule SanbaseWeb.Graphql.UserSettingsTypes do
  use Absinthe.Schema.Notation

  object :user_settings do
    field(:has_telegram_connected, :boolean)
    field(:signal_notify_telegram, :boolean)
    field(:signal_notify_email, :boolean)
    field(:subscribed_to_newsletter, :boolean)
  end
end
