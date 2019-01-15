defmodule SanbaseWeb.Graphql.UserSettingsTypes do
  use Absinthe.Schema.Notation

  import Absinthe.Resolution.Helpers
  alias SanbaseWeb.Graphql.SanbaseRepo

  enum(:channel, values: [:telegram, :email])

  object :user_settings do
    # field(:user, non_null(:user), resolve: dataloader(SanbaseRepo))
    field(:telegram_url, :string)
    field(:signal_notify_telegram, :boolean)
    field(:signal_notify_email, :boolean)
  end
end
