defmodule SanbaseWeb.Plug.BotLoginPlug do
  @moduledoc ~s"""
  Checks the path if it is really coming from the sanbase bot. The endpoint is a secret
  and is only known by the bot.
  """

  @behaviour Plug

  import Plug.Conn

  alias Sanbase.Utils.Config

  def init(opts), do: opts

  def call(%{params: %{"path" => path}} = conn, _) do
    expected = bot_login_endpoint()

    if is_binary(expected) and is_binary(path) and
         Plug.Crypto.secure_compare(path, expected) do
      conn
    else
      conn
      |> send_resp(403, "Unauthorized")
      |> halt()
    end
  end

  def call(conn, _) do
    conn
    |> send_resp(403, "Unauthorized")
    |> halt()
  end

  defp bot_login_endpoint(), do: Config.module_get(__MODULE__, :bot_login_endpoint)
end
