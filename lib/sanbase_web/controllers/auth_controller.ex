defmodule SanbaseWeb.AuthController do
  @moduledoc """
  Auth controller responsible for handling Ueberauth responses
  """

  use SanbaseWeb, :controller

  plug(Ueberauth)

  alias Sanbase.Auth.User
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
         {:ok, user} <- User.find_or_insert_by(:email, email, %{is_registered: true}),
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
    twitter_id = auth.uid
    email = auth.info.email

    with {:ok, user} <- twitter_login(email, twitter_id),
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

  # In case the twitter profile has an email address, try fetching the user with
  # that email and set its twitter_id to the given id. This is done so existing
  # account can be linked to a twitter account when email addresses match.
  # The User.update_twitter_id/2 is no-op if the user with that email already exists and
  # has that twitter_id set. So this results in a single DB call in all cases
  # except the first time twitter login is used.
  defp twitter_login(email, twitter_id) when is_binary(email) and byte_size(email) > 0 do
    with {:ok, user} <- User.find_or_insert_by(:email, email, %{is_registered: true}),
         {:ok, user} <- User.update_field(user, :twitter_id, twitter_id) do
      {:ok, user}
    end
  end

  defp twitter_login(_email, twitter_id) do
    User.find_or_insert_by(:twitter_id, twitter_id, %{is_registered: true})
  end
end
