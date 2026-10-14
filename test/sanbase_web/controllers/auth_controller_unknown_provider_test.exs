defmodule SanbaseWeb.AuthControllerUnknownProviderTest do
  use SanbaseWeb.ConnCase, async: true

  @moduletag capture_log: true

  test "GET /auth/<unknown> returns 404", %{conn: conn} do
    conn = get(conn, "/auth/" <> URI.encode("(select 198766*667891)"))

    assert conn.status == 404
  end

  test "GET /auth/<unknown>/callback returns 404", %{conn: conn} do
    conn = get(conn, "/auth/facebook/callback")

    assert conn.status == 404
  end
end
