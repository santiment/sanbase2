defmodule SanbaseWeb.Plug.BasicAuth do
  @moduledoc ~s"""
  Checks the path if it is really comming from telegram. The endpoint is a secret
  and is only known by telegram.
  """

  @behaviour Plug

  alias Sanbase.Utils.Config

  def init(opts), do: opts

  def call(conn, _) do
    Plug.BasicAuth.basic_auth(conn,
      username: Config.module_get(__MODULE__, :username),
      password: Config.module_get(__MODULE__, :password)
    )
  end
end
