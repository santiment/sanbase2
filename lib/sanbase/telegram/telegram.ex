defmodule Sanbase.Telegram do
  @moduledoc ~s"""
  Module for handling the Telegram BOT functionality.
  It is providing functions for:
  1. Deep linking sanbase and telegram accounts
  2. Sending messages.
  """

  require Logger
  alias Sanbase.Utils.Config

  import Sanbase.Utils.ErrorHandling, only: [changeset_errors_string: 1]
  import Sanbase.Utils.Transform, only: [maybe_unwrap_ok_value: 1]

  alias Sanbase.Accounts.{User, Settings, UserSettings}
  alias Sanbase.Telegram.UserToken

  @type message :: String.t() | iolist()

  use Tesla
  @rate_limiting_server :telegram_bot_rate_limiting_server
  alias Sanbase.ExternalServices.{RateLimiting, ErrorCatcher}
  plug(ErrorCatcher.Middleware)
  plug(RateLimiting.Middleware, name: @rate_limiting_server)

  plug(
    Tesla.Middleware.BaseUrl,
    "https://api.telegram.org/bot#{Config.module_get(__MODULE__, :token)}/"
  )

  plug(Tesla.Middleware.Headers, [{"Content-Type", "application/json"}])

  def channel_id_valid?(chat_id) do
    params = %{chat_id: chat_id} |> Jason.encode!()

    with {:ok, %Tesla.Env{status: 200, body: body}} <- post("getChat", params),
         {:ok, %{"ok" => true}} <- Jason.decode(body) do
      true
    else
      _ -> false
    end
  end

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
      %Settings{telegram_chat_id: chat_id} when is_integer(chat_id) ->
        send_message_to_chat_id(chat_id, text, user)

      %Settings{telegram_chat_id: chat_id} ->
        {:error,
         """
         Cannot send message to user with id #{user.id}. Reason: There is no telegram_chat id for that user.
         Current value is: #{chat_id}
         """}
    end
  end

  @doc ~s"""
  Send aj telegram message to a given chat_id.
  The chat_id is just the chat_id of the telegram chat if it is sending messages to a user
  The chat_id is the `@<alias name>` of a channel when the channel is pubic
  The chat_id is `-100<chat id>` when the channel is private
  """
  @spec send_message_to_chat_id(non_neg_integer(), message, nil | %User{}) ::
          {:ok, any()} | {:error, String.t()}
  def send_message_to_chat_id(chat_id, text, user \\ nil) do
    content =
      %{
        parse_mode: "markdown",
        chat_id: chat_id,
        text: text,
        disable_web_page_preview: true
      }
      |> Jason.encode!()

    case post("sendMessage", content) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Tesla.Env{status: 400, body: json_body}} ->
        body = Jason.decode!(json_body)

        error_msg =
          "Telegram message not senterror 400. Reason: #{Map.get(body, "description", "Bad request")}"

        Logger.info(error_msg)
        {:error, error_msg}

      {:ok, %Tesla.Env{status: 403}} ->
        user_data = if user, do: "User with id #{user.id}", else: "User"

        error_msg =
          "Telegram message not sent error 403. Reason: #{user_data} has blocked the telegram bot."

        Logger.info(error_msg)
        {:error, error_msg}

      {:ok, %Tesla.Env{status: 404, body: json_body}} ->
        body = Jason.decode!(json_body)

        error_msg =
          "Telegram message not sent error 404. Reason: #{Map.get(body, "description", "Chat ID not found")}"

        Logger.info(error_msg)
        {:error, error_msg}

      error ->
        Logger.warning("Telegram message not sent. Reason: #{inspect(error)}")
        {:error, "Telegram message not sent."}
        error
    end
  end

  def send_image(chat_id, image_url, reply_to_message_id) do
    content =
      %{
        chat_id: chat_id,
        photo: image_url,
        reply_to_message_id: reply_to_message_id
      }
      |> Jason.encode!()

    post("sendPhoto", content)
  end

  def send_photo_by_file_content(chat_id, file_content, reply_to_message_id) do
    body =
      Tesla.Multipart.new()
      |> Tesla.Multipart.add_file_content(
        file_content,
        "photo_#{chat_id}_#{reply_to_message_id}.jpeg",
        name: "photo"
      )
      |> Tesla.Multipart.add_field("chat_id", to_string(chat_id))

    body =
      if reply_to_message_id do
        body
        |> Tesla.Multipart.add_field("reply_to_message_id", to_string(reply_to_message_id))
      else
        body
      end

    post("sendPhoto", body)
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
            error_msg = changeset_errors_string(changeset)

            Logger.error(
              "Cannot set telegram chat id for user id #{user_id}. Reason: #{error_msg}"
            )

            {:error, error_msg}
        end

        :ok

      _ ->
        {:error, "There is not user connected with the provided user token."}
    end
  end

  def telegram_channel_members_count(telegram_chat_name) do
    telegram_channel_members_count_query(telegram_chat_name)
    |> Sanbase.ClickhouseRepo.query_transform(fn [dt, value] ->
      %{
        datetime: DateTime.from_unix!(dt),
        members_count: value
      }
    end)
    |> maybe_unwrap_ok_value()
  end

  # private

  defp telegram_channel_members_count_query(telegram_chat_name) do
    sql = """
    SELECT
      toUnixTimestamp(timestamp),
      participants_count
    FROM tg_participants_count
    WHERE
      source = {{telegram_chat_name}} AND
      timestamp = (SELECT max(timestamp) FROM tg_participants_count WHERE source = {{telegram_chat_name}})
    """

    params = %{telegram_chat_name: telegram_chat_name}

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  # Private functions

  defp generate_link(user_token) do
    "https://telegram.me/#{Config.module_get(__MODULE__, :bot_username)}?start=#{user_token}"
  end
end
