defmodule Sanbase.Alerts do
  @moduledoc ~s"""
  Context module for alert (UserTrigger) orchestration. Web callers should go
  through this module rather than reaching into `UserTrigger` and `Telegram`
  separately.
  """

  alias Sanbase.Accounts.User
  alias Sanbase.Alert.{Trigger, UserTrigger}
  alias Sanbase.Repo
  alias Sanbase.Telegram

  @doc ~s"""
  Create a UserTrigger for `user`, preload its `:tags`, and notify the user via
  Telegram. The Telegram notification is best-effort and is skipped on failure.
  """
  @spec create_trigger(User.t(), map()) ::
          {:ok, UserTrigger.t()} | {:error, Ecto.Changeset.t() | String.t()}
  def create_trigger(%User{} = user, args) do
    with {:ok, %UserTrigger{} = user_trigger} <- UserTrigger.create_user_trigger(user, args) do
      user_trigger = Repo.preload(user_trigger, :tags)
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
