defmodule SanbaseWeb.TelegramController do
  use SanbaseWeb, :controller

  alias Sanbase.Telegram

  def index(conn, %{"message" => %{"text" => "/start " <> user_token}} = params) do
    %{"message" => %{"chat" => %{"id" => chat_id}}} = params
    Telegram.store_chat_id(user_token, chat_id)

    conn
    |> resp(200, "ok")
    |> send_resp()
  end

  def index(conn, _params) do
    conn
    |> resp(200, "ok")
    |> send_resp()
  end
end
