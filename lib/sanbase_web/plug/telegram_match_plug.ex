defmodule SanbaseWeb.Plug.TelegramMatchPlug do
  @moduledoc ~s"""
  Checks the path if it is really comming from telegram. The endpoint is a secret
  and is only known by telegram.
  """

  @behaviour Plug

  import Plug.Conn

  require Sanbase.Utils.Config, as: Config

  def init(opts), do: opts

  def call(%{params: %{"path" => path}} = conn, _) do
    case path === telegram_endpoint() do
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

  defp telegram_endpoint(), do: Config.module_get(Sanbase.Telegram, :telegram_endpoint)
end
