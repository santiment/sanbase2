defmodule Sanbase.ExAdmin.Auth.UserSettings do
  use ExAdmin.Register

  alias Sanbase.Auth.{User, UserSettings}

  register_resource Sanbase.Auth.UserSettings do
    form user_settings do
      inputs do
        input(
          user_settings,
          :user,
          collection: from(u in User, order_by: u.username) |> Sanbase.Repo.all()
        )

        input(user_settings, :signal_notify_email)
        input(user_settings, :signal_notify_telegram)
        input(user_settings, :telegram_url)
      end
    end

    show user_settings do
      attributes_table(all: true)
    end
  end
end
