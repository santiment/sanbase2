defmodule SanbaseWeb.TestTelegramController do
  use SanbaseWeb, :controller

  def send_message(conn, %{"chat_id" => _, "parse_mode" => "markdown", "text" => _} = params) do
    conn
    |> resp(200, "ok")
    |> send_resp()
  end

  def send_message(conn, _) do
    conn
    |> resp(404, "not found")
    |> send_resp()
  end
end
