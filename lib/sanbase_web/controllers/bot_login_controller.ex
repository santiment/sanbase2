defmodule SanbaseWeb.BotLoginController do
  use SanbaseWeb, :controller

  require Logger

  alias Sanbase.Auth.User

  def index(conn, _params) do
    user = User |> Sanbase.Repo.get_by(email: User.sanbase_bot_email())
    {:ok, token, _claims} = SanbaseWeb.Guardian.encode_and_sign(user, %{salt: user.salt})

    conn
    |> resp(200, token)
    |> send_resp()
  end
end
