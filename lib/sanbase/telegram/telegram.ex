defmodule Sanbase.Telegram do
  @moduledoc ~s"""
  Module for handling the Telegram BOT functionality.
  It is providing functions for:
  1. Deep linking sanbase and telegram accounts
  2. Sending messages.
  """

  require Sanbase.Utils.Config, as: Config
  require Logger
  alias Sanbase.Auth.User
  alias Sanbase.Telegram.UserToken

  @type message :: String.t() | iolist()
  @authorization_token Config.get(:token)
  @bot_username Config.get(:username)

  @spec get_or_create_deep_link(non_neg_integer()) :: String.t()
  def get_or_create_deep_link(user_id) do
    case UserToken.by_user_id(user_id) do
      %UserToken{token: token, user_id: ^user_id} ->
        generate_link(token)

      nil ->
        {:ok, %UserToken{user_id: ^user_id, token: token}} = UserToken.generate(user_id)
        generate_link(token)
    end
  end

  def revoke_deep_link(user_id) do
    case UserToken.by_user_id(user_id) do
      %UserToken{token: token, user_id: ^user_id} ->
        UserToken.revoke(token, user_id)

      nil ->
        :ok
    end
  end

  @spec send_message(%User{}, message) :: :ok | {:error, String.t()}
  def send_message(%User{id: _user_id}, text) do
    # chat_id = UserSettings.user_telegram_chat_id(user_id)
    send_message_to_chat_id(123_456, text)
  end

  @spec send_message_to_chat_id(non_neg_integer(), message) :: :ok | {:error, String.t()}
  def send_message_to_chat_id(chat_id, text) do
    HTTPoison.post(
      "https://api.telegram.org/bot#{@authorization_token}/sendMessage",
      %{
        parse_mode: "markdown",
        chat_id: chat_id,
        text: text
      }
      |> Jason.encode!(),
      [{"Content-Type", "application/json"}]
    )
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200}} -> :ok
      _ -> {:error, "Telegram message not sent."}
    end
  end

  @spec store_chat_id(String.t(), non_neg_integer()) :: :ok | {:error, String.t()}
  def store_chat_id(user_token, chat_id) do
    case UserToken.by_token(user_token) do
      %UserToken{token: ^user_token, user_id: user_id} ->
        # UserSettings.set_telegram_chat_id(user_id, chat_id)
        Logger.info("Setting the chat_id #{chat_id} to the user #{user_id}")
        :ok

      _ ->
        {:error, "User token not existent"}
    end
  end

  # Private functions

  defp generate_link(user_token) do
    "https://telegram.me/#{@bot_username}?start=#{user_token}"
  end
end
