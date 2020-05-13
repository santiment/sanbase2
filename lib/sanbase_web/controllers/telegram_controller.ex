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
    🤖Beep boop, Santiment Signals bot here!

    You've succesfully connected your Sanbase and Telegram accounts.

    To receive alerts in this chat, enable the Telegram channel in a Sanbase signal.

    Haven’t created any signals yet? Start [here](https://app.santiment.net/sonar/my-signals).
    """
  end
end
