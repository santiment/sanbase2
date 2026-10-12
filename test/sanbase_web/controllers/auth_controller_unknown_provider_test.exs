defmodule SanbaseWeb.AuthControllerUnknownProviderTest do
  # SANBASE-BACKEND-PROD-2Q: unknown providers crashed Ueberauth.run_request/4
  use SanbaseWeb.ConnCase, async: true

  @moduletag capture_log: true

  for provider <- ["facebook", "(select 198766*667891)", "github"] do
    test "GET /auth/#{provider} returns 404", %{conn: conn} do
      conn = get(conn, "/auth/" <> URI.encode(unquote(provider)))

      assert conn.status == 404
    end
  end

  test "GET /auth/<unknown>/callback returns 404", %{conn: conn} do
    conn = get(conn, "/auth/facebook/callback")

    assert conn.status == 404
  end
end
