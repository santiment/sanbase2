defmodule SanbaseWeb.BotLoginController do
  use SanbaseWeb, :controller

  alias Sanbase.Accounts.User

  require Logger

  def index(conn, %{"user" => user_idx}) do
    User
    |> Sanbase.Repo.get_by(email: User.sanbase_bot_email(user_idx))
    |> send_response(conn)
  end

  def index(conn, _params) do
    User
    |> Sanbase.Repo.get_by(email: User.sanbase_bot_email())
    |> send_response(conn)
  end

  defp send_response(user, conn) do
    device_data = SanbaseWeb.Guardian.device_data(conn)

    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user, device_data)

    conn
    |> SanbaseWeb.Guardian.add_jwt_tokens_to_conn_session(jwt_tokens)
    |> resp(200, jwt_tokens.access_token)
    |> send_resp()
  end
end
