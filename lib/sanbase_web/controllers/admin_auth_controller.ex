defmodule SanbaseWeb.AdminAuthController do
  @moduledoc """
  Auth controller responsible for handling Ueberauth responses
  """

  use SanbaseWeb, :controller

  require Logger

  def handle_admin_email_auth(conn, _params) do
    conn
    |> redirect(to: ~p"/admin")
  end

  def logout(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> SanbaseWeb.AdminUserAuth.log_out_user()
  end
end
