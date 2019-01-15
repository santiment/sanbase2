defmodule SanbaseWeb.Graphql.UserSettingsTypes do
  use Absinthe.Schema.Notation

  object :user_settings do
    field(:telegram_url, :string)
    field(:signal_notify_telegram, :boolean)
    field(:signal_notify_email, :boolean)
  end
end
