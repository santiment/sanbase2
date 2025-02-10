defmodule SanbaseWeb.TelegramController do
  use SanbaseWeb, :controller

  alias Sanbase.Telegram

  def index(conn, %{"message" => %{"text" => "/start " <> user_token}} = params) do
    %{"message" => %{"chat" => %{"id" => chat_id}}} = params

    case Telegram.store_chat_id(user_token, chat_id) do
      :ok ->
        Telegram.send_message_to_chat_id(chat_id, welcome_message())

        conn
        |> resp(200, "ok")
        |> send_resp()

      {:error, error} ->
        conn
        |> resp(400, error)
        |> send_resp()
    end
  end

  def index(conn, _params) do
    conn
    |> resp(200, "ok")
    |> send_resp()
  end

  defp welcome_message do
    ~s"""
    🤖Beep boop, Santiment Alerts bot here!

    You've succesfully connected your Sanbase and Telegram accounts.

    To receive alerts in this chat, enable the Telegram channel in an alert settings.

    Haven’t created any alerts yet? Start [here](#{SanbaseWeb.Endpoint.my_alerts_url()}).
    """
  end
end
