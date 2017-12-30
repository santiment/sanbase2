defmodule SanbaseWeb.RootController do
  use SanbaseWeb, :controller

  # Used in production mode to serve the reactjs application
  def index(conn, _params) do
    conn
    |> put_resp_header("content-type", "text/html; charset=utf-8")
    |> Plug.Conn.send_file(200, path("priv/static/index.html"))
  end

  def react_env(conn, _params) do
    conn
    |> put_resp_header("content-type", "text/html; charset=utf-8")
    |> render("env.js")
  end

  defp path(file) do
    Application.app_dir(:sanbase)
    |> Path.join(file)
  end
end
