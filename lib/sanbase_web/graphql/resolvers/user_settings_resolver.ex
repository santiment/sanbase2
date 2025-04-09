defmodule SanbaseWeb.Graphql.Resolvers.UserSettingsResolver do
  require Logger

  import Sanbase.Utils.ErrorHandling, only: [changeset_errors: 1, changeset_errors_string: 1]

  alias Sanbase.Accounts.{User, UserSettings}

  def settings(_root, _args, %{context: %{auth: %{auth_method: :basic}}}) do
    {:ok, %{}}
  end

  def settings(%User{} = user, _args, _resolution) do
    {:ok, UserSettings.settings_for(user)}
  end

  def alerts_per_dy_limit_left(_settings, _args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserSettings.max_alerts_to_send(current_user)
  end

  def update_user_settings(_root, %{settings: settings}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    settings = maybe_update_settings_args(settings)

    case UserSettings.update_settings(current_user, settings) do
      {:ok, %{settings: settings}} ->
        {:ok, settings}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Cannot update user settings. Reason: #{changeset_errors_string(changeset)}"}

      {:error, error} ->
        {:error, error}
    end
  end

  def settings_toggle_channel(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    args = maybe_update_settings_args(args)

    UserSettings.toggle_notification_channel(current_user, args)
    |> handle_toggle_result()
  end

  # Private functions

  defp handle_toggle_result(result) do
    case result do
      {:ok, us} ->
        {:ok, us.settings}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot toggle user setting", details: changeset_errors(changeset)
        }
    end
  end

  defp maybe_update_field(%{} = settings, old_key, new_key) do
    case Map.has_key?(settings, old_key) do
      true -> Map.put(settings, new_key, settings[old_key])
      false -> settings
    end
  end

  # Fill the new values from the old, deprecated fields.
  defp maybe_update_settings_args(settings) do
    settings
    |> maybe_update_field(:signal_notify_telegram, :alert_notify_telegram)
    |> maybe_update_field(:signal_notify_email, :alert_notify_email)
    |> maybe_update_field(:signals_per_day_limit, :alerts_per_day_limit)
  end
end
