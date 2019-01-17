defmodule Sanbase.Telegram do
  @moduledoc ~s"""
  Module for handling the Telegram BOT functionality.
  It is providing functions for:
  1. Deep linking sanbase and telegram accounts
  2. Sending messages.
  """

  require Sanbase.Utils.Config, as: Config
  require Logger
  alias Sanbase.Auth.{User, Settings, UserSettings}
  alias Sanbase.Telegram.UserToken

  @type message :: String.t() | iolist()
  @authorization_token Config.get(:token)
  @bot_username Config.get(:username)

  use Tesla
  @rate_limiting_server :telegram_bot_rate_limiting_server
  alias Sanbase.ExternalServices.{RateLimiting, ErrorCatcher}
  plug(ErrorCatcher.Middleware)
  plug(RateLimiting.Middleware, name: @rate_limiting_server)
  plug(Tesla.Middleware.BaseUrl, "https://api.telegram.org/bot#{@authorization_token}/")
  plug(Tesla.Middleware.Headers, [{"Content-Type", "application/json"}])

  @doc ~s"""
  Get the already existing deeplink or creates a new one if there is none.
  A telegram bot and a user can have at most 1 chat channel, so we can have at most
  1 link at a time.
  """
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

  @doc ~s"""
  Revoke the telegram deeplink for a given user, if any. The generated token will no
  longer be connected to that user. Future calls with that token won't have any effect
  """
  @spec revoke_deep_link(non_neg_integer()) :: :ok
  def revoke_deep_link(user_id) do
    case UserToken.by_user_id(user_id) do
      %UserToken{token: token, user_id: ^user_id} ->
        UserToken.revoke(token, user_id)
        :ok

      nil ->
        :ok
    end
  end

  @doc ~s"""
  Send a telegram message to a given user. Bots can't send message to users dirrectly.
  The user must have already followed the specially generated telegram deeplink that
  will connect snabase and telegram accounts. After this is done a special chat_id
  will be known and the bot can send message to such chats
  """
  @spec send_message(%User{}, message) :: :ok | {:error, String.t()}
  def send_message(%User{} = user, text) do
    case UserSettings.settings_for(user) do
      nil ->
        {:error,
         "Cannot send message to user with id #{user.id}. Reason: There is no telegram_chat id for that user"}

      %Settings{telegram_chat_id: chat_id} when is_integer(chat_id) ->
        send_message_to_chat_id(chat_id, text)
    end
  end

  @doc ~s"""
  Send a telegram message to a given chat_id
  """
  @spec send_message_to_chat_id(non_neg_integer(), message) :: :ok | {:error, String.t()}
  def send_message_to_chat_id(chat_id, text) do
    post(
      "sendMessage",
      %{
        parse_mode: "markdown",
        chat_id: chat_id,
        text: text
      }
      |> Jason.encode!()
    )
    |> case do
      {:ok, %Tesla.Env{status: 200}} -> :ok
      _ -> {:error, "Telegram message not sent."}
    end
  end

  @doc ~s"""
  A message is received at an endpoint known only to telegram and there is a
  start token present. Match the token to a user and store the telegram chat_id
  in their settings. If this succeeds the telegram-sanbase connection is done.
  """
  @spec store_chat_id(String.t(), non_neg_integer()) :: :ok | {:error, String.t()}
  def store_chat_id(user_token, chat_id) do
    case UserToken.by_token(user_token) do
      %UserToken{token: ^user_token, user_id: user_id} ->
        Logger.info("Setting the chat_id #{chat_id} to the user #{user_id}")

        UserSettings.set_telegram_chat_id(user_id, chat_id)
        |> case do
          {:ok, _} ->
            :ok

          {:error, changeset} ->
            Logger.error(
              "Cannot set telegram chat id for user id #{user_id}. Reason: #{inspect(changeset)}"
            )

            {:error, changeset}
        end

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
