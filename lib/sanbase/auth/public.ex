defmodule Sanbase.Auth.User.Public do
  alias Sanbase.Auth.User
  alias Sanbase.Auth.UserSettings

  @sensitive_fields [:email, :twitter_id]

  def hide_private_data(%User{} = user) do
    case UserSettings.settings_for(user) do
      %{hide_privacy_data: false} ->
        user

      _ ->
        Enum.reduce(@sensitive_fields, user, fn field, user_acc ->
          Map.put(user_acc, field, "<email hidden>")
        end)
    end
  end
end
