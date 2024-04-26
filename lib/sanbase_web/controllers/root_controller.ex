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

  def sleep(conn, params) do
    sleep_time_ms = (params["time"] |> String.to_integer()) * 1000
    Process.sleep(sleep_time_ms)

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "OK")
  end

  defp path(file) do
    Application.app_dir(:sanbase)
    |> Path.join(file)
  end
end
