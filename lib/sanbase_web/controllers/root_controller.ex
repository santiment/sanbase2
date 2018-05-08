defmodule SanbaseWeb.RootController do
  use SanbaseWeb, :controller

  alias Sanbase.Oauth2.Hydra

  # Used in production mode to serve the reactjs application
  def index(conn, _params) do
    conn
    |> put_resp_header("content-type", "text/html; charset=utf-8")
    |> Plug.Conn.send_file(200, path("priv/static/index.html"))
  end

  def consent(
        conn,
        %{
          "consent" => consent,
          "name" => name,
          "email" => email
        } = params
      ) do
    {:ok, access_token} = Hydra.get_access_token()
    {:ok, redirect_url} = Hydra.get_consent_data(consent, access_token)
    :ok = Hydra.accept_consent(consent, access_token, %{name: name, email: email})
    redirect(conn, external: redirect_url)
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
