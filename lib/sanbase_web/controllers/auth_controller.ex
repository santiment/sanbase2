defmodule SanbaseWeb.AuthController do
  @moduledoc """
  Auth controller responsible for handling Ueberauth responses
  """

  use SanbaseWeb, :controller

  plug(Ueberauth)

  alias Ueberauth.Strategy.Helpers

  def request(conn, _params) do
    render(conn, "request.html", callback_url: Helpers.callback_url(conn))
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "You have been logged out!")
    |> configure_session(drop: true)
    |> redirect(to: "/")
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate.")
    |> redirect(to: "/")
  end

  def callback(%{assigns: %{ueberauth_auth: %{provider: :google} = auth}} = conn, _params) do
    IO.inspect(auth, label: "AUTH")


    case {:error, :not_found} do
      {:error, :not_found} ->
        conn
        |> put_flash(:info, "Successfully authenticated.")
        |> put_session(:current_user, %Sanbase.Auth.User{id: 1})
        |> redirect(to: "/")

      student ->
        conn
        |> put_flash(:info, "Successfully authenticated.")
        |> redirect(to: "/")
    end
  end
end
