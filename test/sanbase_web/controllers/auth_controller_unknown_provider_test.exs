defmodule SanbaseWeb.AuthControllerUnknownProviderTest do
  # Reproduces SANBASE-BACKEND-PROD-2Q:
  # FunctionClauseError: no function clause matching in Ueberauth.run_request/4
  #
  # The route is `get "/auth/:provider", AuthController, :request`, and request/2 does
  # `Ueberauth.run_request(conn, provider, @providers[provider])`. For any provider other
  # than "google"/"twitter" (scanners hit e.g. /auth/(select%20198766*667891),
  # /auth/facebook, /auth/github) `@providers[provider]` is nil and run_request/4 raises,
  # producing a 500 and a Sentry event. Unknown providers should get a 404.
  use SanbaseWeb.ConnCase, async: true

  @moduletag capture_log: true

  for provider <- ["facebook", "(select 198766*667891)", "github"] do
    test "GET /auth/#{provider} returns 404 instead of crashing", %{conn: conn} do
      conn = get(conn, "/auth/" <> URI.encode(unquote(provider)))

      assert conn.status == 404
    end
  end

  test "GET /auth/<unknown>/callback returns 404 instead of crashing", %{conn: conn} do
    conn = get(conn, "/auth/facebook/callback")

    assert conn.status == 404
  end
end
