defmodule Sanbase.ExAdmin.Auth.UserSettings do
  use ExAdmin.Register

  alias Sanbase.Auth.UserSettings

  register_resource Sanbase.Auth.UserSettings do
    action_items(only: [:show])

    index do
      column(:user)
      column(:settings, fn us -> Poison.encode!(us.settings) end)
    end

    show user_settings do
      attributes_table do
        row(:user)
      end

      panel "Settings" do
        table_for([user_settings]) do
          column("Settings", &Poison.encode!(&1.settings))
        end
      end
    end
  end
end
