defmodule SanbaseWeb.Plug.TelegramMatchPlug do
  @moduledoc ~s"""
  Checks the path if it is really coming from telegram. The endpoint is a secret
  and is only known by telegram.
  """

  @behaviour Plug

  import Plug.Conn

  alias Sanbase.Utils.Config

  def init(opts), do: opts

  def call(%{params: %{"path" => path}} = conn, _) do
    case valid_path?(path, telegram_endpoint()) do
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

  defp valid_path?(path, endpoint) when is_binary(path) and is_binary(endpoint) do
    Plug.Crypto.secure_compare(path, endpoint)
  end

  defp valid_path?(_path, _endpoint), do: false

  defp telegram_endpoint(), do: Config.module_get(Sanbase.Telegram, :telegram_endpoint)
end
