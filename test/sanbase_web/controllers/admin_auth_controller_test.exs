defmodule SanbaseWeb.AdminAuthControllerTest do
  @moduledoc """
  The email-login landing redirect. A login that was triggered by a bounce off a
  protected page (e.g. a shared deep research link) must return the user there —
  such pages need no admin panel role, while the `/admin` fallback 401s for
  role-less users.

  In the :test compile env `AdminEmailAuthPlug` allows passwordless login, so a
  plain GET with an email logs in without a token.
  """

  use SanbaseWeb.ConnCase, async: false

  test "email login redirects back to the stored return path and clears it", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{user_return_to: "/deep_research/shared/some-id"})
      |> get("/admin_auth/email_login", %{"email" => "sharee@santiment.net"})

    assert redirected_to(conn) == "/deep_research/shared/some-id"
    assert get_session(conn, :user_return_to) == nil
  end

  test "email login without a stored return path lands on /admin", %{conn: conn} do
    conn = get(conn, "/admin_auth/email_login", %{"email" => "direct@santiment.net"})

    assert redirected_to(conn) == "/admin"
  end
end
