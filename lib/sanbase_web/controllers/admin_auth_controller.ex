defmodule SanbaseWeb.AdminAuthController do
  @moduledoc """
  Auth controller responsible for handling Ueberauth responses
  """

  use SanbaseWeb, :controller

  require Logger

  @doc """
  Land the user after a successful admin email login.

  Redirects to the `:user_return_to` path stored in the session by
  `SanbaseWeb.AdminUserAuth.assign_current_user_or_redirect/2` when an
  unauthenticated request was bounced to the login page (e.g. a shared deep
  research link, which needs no admin panel role), clearing it from the
  session; falls back to `/admin` when no return path is stored.
  """
  @spec handle_admin_email_auth(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def handle_admin_email_auth(conn, _params) do
    return_to = get_session(conn, :user_return_to) || ~p"/admin"

    conn
    |> delete_session(:user_return_to)
    |> redirect(to: return_to)
  end

  def logout(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> SanbaseWeb.AdminUserAuth.log_out_user()
  end
end
