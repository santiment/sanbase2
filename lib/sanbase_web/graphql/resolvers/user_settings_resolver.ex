defmodule SanbaseWeb.Graphql.Resolvers.UserSettingsResolver do
  require Logger

  alias Sanbase.Auth.{User, UserSettings}
  alias SanbaseWeb.Graphql.Helpers.Utils
  alias Sanbase.Repo

  def settings_toggle_telegram_channel(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserSettings.toggle_notification_channel(current_user, :signal_notify_telegram)
    |> handle_toggle_result(:signal_notify_telegram)
  end

  def settings_toggle_email_channel(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserSettings.toggle_notification_channel(current_user, :signal_notify_email)
    |> handle_toggle_result(:signal_notify_email)
  end

  def settings_generate_telegram_url(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserSettings.generate_telegram_url(current_user)
    |> case do
      {:ok, %UserSettings{telegram_url: telegram_url}} ->
        {:ok, telegram_url}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error,
         message: "Cannot generate telegram url!", details: Utils.error_details(changeset)}

      {:error, error_string} ->
        {:error, error_string}
    end
  end

  defp handle_toggle_result(result, channel) do
    case result do
      {:ok, us} ->
        {:ok, us |> Map.get(channel)}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot toggle user setting", details: Utils.error_details(changeset)
        }
    end
  end
end
