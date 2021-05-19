defmodule SanbaseWeb.BotLoginController do
  use SanbaseWeb, :controller

  require Logger

  alias Sanbase.Accounts.User

  def index(conn, %{"user" => user_idx}) do
    Sanbase.Repo.get_by(User, email: User.sanbase_bot_email(user_idx))
    |> send_response(conn)
  end

  def index(conn, _params) do
    Sanbase.Repo.get_by(User, email: User.sanbase_bot_email())
    |> send_response(conn)
  end

  defp send_response(user, conn) do
    {:ok, token, _claims} = SanbaseWeb.Guardian.encode_and_sign(user, %{})

    conn
    |> Plug.Conn.put_session(:auth_token, token)
    |> resp(200, token)
    |> send_resp()
  end
end
