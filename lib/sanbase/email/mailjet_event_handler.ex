defmodule Sanbase.Email.MailjetEventHandler do
  @moduledoc """
  Handler for Mailjet webhook events.

  This module contains functions for handling different types of Mailjet events
  that are received via webhooks.
  """

  require Logger

  alias Sanbase.Accounts.User
  alias Sanbase.Accounts.UserSettings
  alias Sanbase.Email.{Lists, ListSubscription}
  alias Sanbase.Repo

  @mailjet_list_mapping %{
    "10327896" => :is_subscribed_edu_emails,
    "10327883" => :is_subscribed_metric_updates,
    # dev
    "10326671" => :is_subscribed_metric_updates,
    # stage
    "10326676" => :is_subscribed_metric_updates,
    "61085" => :is_subscribed_monthly_newsletter,
    "-1" => :is_subscribed_biweekly_report
  }

  # Lists registered in Sanbase.Email.Lists are looked up there first.

  @doc """
  Handle an unsubscribe event from Mailjet.

  Updates user settings to turn off the corresponding subscription setting based on the
  Mailjet list ID.

  ## Parameters
    - email: The email address that was unsubscribed
    - list_id: The Mailjet list ID that the user unsubscribed from

  ## Returns
    - {:ok, user} - When the user settings were successfully updated
    - {:error, reason} - When there was an error updating the settings or the user wasn't found
  """
  @spec handle_unsubscribe(String.t(), integer() | String.t()) ::
          {:ok, User.t()} | {:error, :user_not_found | any()}
  def handle_unsubscribe(email, list_id) do
    list_id_str = to_string(list_id)

    case lookup(list_id_str) do
      :error ->
        Logger.warning("Unhandled Mailjet list ID: #{list_id_str} for unsubscribe event")
        {:error, :unknown_list_id}

      {:ok, target} ->
        case Repo.get_by(User, email: email) do
          %User{} = user ->
            unsubscribe(user, target)

          nil ->
            Logger.info("User with email #{email} not found for unsubscribe event")
            {:error, :user_not_found}
        end
    end
  end

  defp unsubscribe(user, {:list, list_key}) do
    Logger.info("Unsubscribing #{user.email} from the #{list_key} list")

    case ListSubscription.set(user.id, list_key, false, :mailjet_unsubscribe) do
      {:ok, _changed?} -> {:ok, UserSettings.settings_for(user, force: true)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp unsubscribe(user, {:setting, setting_key}) do
    settings_update = Map.put(%{}, setting_key, false)
    Logger.info("Updating user settings for #{user.email}: #{inspect(settings_update)}")

    UserSettings.update_settings(user, settings_update)
  end

  defp lookup(list_id_str) do
    case Lists.list_unsubscribed_by(list_id_str) do
      {:ok, list_key} ->
        {:ok, {:list, list_key}}

      :error ->
        case Map.fetch(@mailjet_list_mapping, list_id_str) do
          {:ok, setting_key} -> {:ok, {:setting, setting_key}}
          :error -> :error
        end
    end
  end

  @doc """
  Get the setting key associated with a Mailjet list ID.

  ## Parameters
    - list_id: The Mailjet list ID

  ## Returns
    - {:ok, atom()} - The setting key as an atom
    - {:error, :unknown_list_id} - If the list ID is not mapped to a setting
  """
  @spec get_setting_key_for_list(integer() | String.t()) ::
          {:ok, atom()} | {:error, :unknown_list_id}
  def get_setting_key_for_list(list_id) do
    case lookup(to_string(list_id)) do
      {:ok, {:list, list_key}} -> {:ok, Lists.get!(list_key).setting}
      {:ok, {:setting, setting_key}} -> {:ok, setting_key}
      :error -> {:error, :unknown_list_id}
    end
  end
end
