defmodule SanbaseWeb.Plug.BotLoginPlug do
  @moduledoc ~s"""
  Checks the path if it is really comming from the sanbase bot. The endpoint is a secret
  and is only known by the bot.
  """

  @behaviour Plug

  import Plug.Conn

  require Sanbase.Utils.Config, as: Config

  def init(opts), do: opts

  def call(%{params: %{"path" => path}} = conn, _) do
    case path === bot_login_endpoint() do
      true ->
        conn

      false ->
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

  defp bot_login_endpoint(), do: Config.get(:bot_login_endpoint)
end
