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
    email = auth.extra.raw_info.user["email"]

    with true <- is_binary(email),
         {:ok, user} <- Sanbase.Auth.User.find_or_insert_by_email(email),
         {:ok, token, _claims} <- SanbaseWeb.Guardian.encode_and_sign(user, %{salt: user.salt}) do
      conn
      |> put_flash(:info, "Successfully authenticated.")
      |> put_session(:auth_token, token)
      |> redirect(external: SanbaseWeb.Endpoint.website_url())
    else
      _ ->
        conn
        |> put_flash(:error, "Failed to authenticate.")
        |> redirect(external: SanbaseWeb.Endpoint.website_url())
    end
  end
end
