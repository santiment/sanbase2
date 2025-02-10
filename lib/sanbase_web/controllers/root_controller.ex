defmodule SanbaseWeb.RootController do
  use SanbaseWeb, :controller

  require Logger

  # Used in production mode to serve the reactjs application
  def index(conn, _params) do
    conn
    |> put_resp_header("content-type", "text/html; charset=utf-8")
    |> Plug.Conn.send_file(200, path("priv/static/index.html"))
  end

  def get_routed_conn(conn, _params), do: conn

  def healthcheck(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "")
  end

  defp path(file) do
    :sanbase
    |> Application.app_dir()
    |> Path.join(file)
  end
end
