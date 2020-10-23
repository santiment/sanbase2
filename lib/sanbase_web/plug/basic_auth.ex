defmodule SanbaseWeb.Plug.BasicAuth do
  @moduledoc ~s"""
  Checks the path if it is really comming from telegram. The endpoint is a secret
  and is only known by telegram.
  """

  @behaviour Plug

  require Sanbase.Utils.Config, as: Config

  def init(opts), do: opts

  def call(conn, _) do
    Plug.BasicAuth.basic_auth(conn,
      username: Config.get(:username),
      password: Config.get(:password)
    )
  end
end
