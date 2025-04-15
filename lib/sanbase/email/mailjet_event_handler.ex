defmodule Sanbase.Email.MailjetEventHandler do
  @moduledoc """
  Handler for Mailjet webhook events.

  This module contains functions for handling different types of Mailjet events
  that are received via webhooks.
  """

  require Logger

  alias Sanbase.Accounts.User
  alias Sanbase.Accounts.UserSettings
  alias Sanbase.Repo

  @mailjet_list_mapping %{
    "10327896" => :is_subscribed_edu_emails,
    "10327883" => :is_subscribed_metric_updates,
    # dev
    "10326671" => :is_subscribed_metric_updates,
    # stage
    "10326676" => :is_subscribed_metric_updates,
    "61085" => :is_subscribed_monthly_newsletter,
    # sanr_network_emails
    "10321582" => :is_subscribed_marketing_emails,
    # alpha_naratives_emails
    "10321590" => :is_subscribed_marketing_emails,
    "-1" => :is_subscribed_biweekly_report
  }

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

    case Map.get(@mailjet_list_mapping, list_id_str) do
      nil ->
        Logger.warning("Unhandled Mailjet list ID: #{list_id_str} for unsubscribe event")
        {:error, :unknown_list_id}

      setting_key ->
        case Repo.get_by(User, email: email) do
          %User{} = user ->
            settings_update = Map.put(%{}, setting_key, false)
            Logger.info("Updating user settings for #{email}: #{inspect(settings_update)}")

            case UserSettings.update_settings(user, settings_update) do
              {:ok, updated_settings} ->
                {:ok, updated_settings}

              {:error, reason} ->
                {:error, reason}
            end

          nil ->
            Logger.info("User with email #{email} not found for unsubscribe event")
            {:error, :user_not_found}
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
    list_id_str = to_string(list_id)

    case Map.get(@mailjet_list_mapping, list_id_str) do
      nil -> {:error, :unknown_list_id}
      setting_key -> {:ok, setting_key}
    end
  end
end
