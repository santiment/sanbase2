defmodule Sanbase.Alerts do
  @moduledoc "Alert (UserTrigger) operations for the web layer."

  alias Sanbase.Accounts.User
  alias Sanbase.Alert.{Trigger, UserTrigger}
  alias Sanbase.Telegram

  @doc ~s"""
  Create a trigger and confirm it to the user on Telegram. The message is sent
  synchronously; a failed send does not fail the creation.
  """
  def create_trigger(%User{} = user, args) do
    with {:ok, %UserTrigger{} = user_trigger} <- UserTrigger.create_user_trigger(user, args) do
      _ = notify_trigger_created(user, args)
      {:ok, user_trigger}
    end
  end

  defp notify_trigger_created(%User{} = user, args) do
    Telegram.send_message(user, build_trigger_created_message(args))
  end

  defp build_trigger_created_message(args) do
    type = Trigger.human_readable_settings_type(args.settings["type"])
    description = if args[:description], do: "\nDescription: #{args[:description]}"

    """
    Successfully created a new alert of type: #{type}

    Title: #{args.title}#{description}

    This bot will send you a message when the alert triggers 🤖
    """
  end
end
