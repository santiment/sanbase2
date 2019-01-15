defmodule SanbaseWeb.Graphql.Resolvers.UserSettingsResolver do
  require Logger

  alias Sanbase.Auth.{User, UserSettings}
  alias SanbaseWeb.Graphql.Helpers.Utils
  alias Sanbase.Repo

  def settings(%User{} = user, _args, _resolution) do
    settings =
      user
      |> Repo.preload(:user_settings)
      |> Map.get(:user_settings)
      |> case do
        nil ->
          {:ok, nil}

        %UserSettings{} = us ->
          {:ok, us}
      end
  end

  def settings_toggle_channel(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserSettings.toggle_notification_channel(current_user, args)
    |> handle_toggle_result()
  end

  def settings_generate_telegram_url(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserSettings.generate_telegram_url(current_user)
    |> case do
      {:ok, %UserSettings{telegram_url: telegram_url} = us} ->
        {:ok, us}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error,
         message: "Cannot generate telegram url!", details: Utils.error_details(changeset)}

      {:error, error_string} ->
        {:error, error_string}
    end
  end

  defp handle_toggle_result(result) do
    case result do
      {:ok, us} ->
        {:ok, us}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot toggle user setting", details: Utils.error_details(changeset)
        }
    end
  end
end
