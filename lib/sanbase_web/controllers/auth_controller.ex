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
    |> configure_session(drop: true)
    |> redirect(to: "/")
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> redirect(to: "/")
  end

  def callback(%{assigns: %{ueberauth_auth: %{provider: :google} = auth}} = conn, _params) do
    email = auth.info.email

    with true <- is_binary(email),
         {:ok, user} <- Sanbase.Auth.User.find_or_insert_by_email(email),
         {:ok, token, _claims} <- SanbaseWeb.Guardian.encode_and_sign(user, %{salt: user.salt}) do
      conn
      |> put_session(:auth_token, token)
      |> redirect(external: SanbaseWeb.Endpoint.website_url())
    else
      _ ->
        conn
        |> redirect(external: SanbaseWeb.Endpoint.website_url())
    end
  end

  def callback(%{assigns: %{ueberauth_auth: %{provider: :twitter} = auth}} = conn, _params) do
    twitter_id_str = auth.uid

    with true <- is_binary(twitter_id_str),
         {:ok, user} <- Sanbase.Auth.User.find_or_insert_by_twitter_id(twitter_id_str),
         {:ok, token, _claims} <- SanbaseWeb.Guardian.encode_and_sign(user, %{salt: user.salt}) do
      conn
      |> put_session(:auth_token, token)
      |> redirect(external: SanbaseWeb.Endpoint.website_url())
    else
      _ ->
        conn
        |> redirect(external: SanbaseWeb.Endpoint.website_url())
    end
  end
end
