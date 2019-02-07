defmodule SanbaseWeb.TelegramController do
  use SanbaseWeb, :controller

  alias Sanbase.Telegram

  def index(conn, %{"message" => %{"text" => "/start " <> user_token}} = params) do
    %{"message" => %{"chat" => %{"id" => chat_id}}} = params
    Telegram.store_chat_id(user_token, chat_id)
    Telegram.send_message_to_chat_id(chat_id, welcome_message())

    conn
    |> resp(200, "ok")
    |> send_resp()
  end

  def index(conn, _params) do
    conn
    |> resp(200, "ok")
    |> send_resp()
  end

  defp welcome_message() do
    ~s"""
    Beep boop! I’m a Santiment Telegram bot :robot:

    This is where you’ll receive notifications for all your preset Santiment signals.

    If you’re seeing this message, you already have a SANbase account which you can use to make changes to the configuration of your signals.

    Visit your account here: #{SanbaseWeb.Endpoint.user_account_url()}
    """
  end
end
