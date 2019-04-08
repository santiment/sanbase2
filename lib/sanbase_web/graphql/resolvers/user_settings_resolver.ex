defmodule SanbaseWeb.Graphql.Resolvers.UserSettingsResolver do
  require Logger

  alias Sanbase.Auth.{User, UserSettings}
  alias SanbaseWeb.Graphql.Helpers.Utils

  def settings(%User{} = user, _args, _resolution) do
    {:ok, UserSettings.settings_for(user)}
  end

  def settings_toggle_channel(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserSettings.toggle_notification_channel(current_user, args)
    |> handle_toggle_result()
  end

  def change_newsletter_subscription(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserSettings.change_newsletter_subscription(current_user, args)
    |> handle_toggle_result()
  end

  defp handle_toggle_result(result) do
    case result do
      {:ok, us} ->
        {:ok, us.settings}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot toggle user setting", details: Utils.error_details(changeset)
        }
    end
  end
end
