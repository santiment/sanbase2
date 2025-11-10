defmodule SanbaseWeb.AuthControllerTest do
  use SanbaseWeb.ConnCase, async: false

  alias SanbaseWeb.AuthController
  alias Sanbase.Factory

  @moduletag capture_log: true

  describe "OAuth flow with sanbase:// redirect URL" do
    setup do
      user = Factory.insert(:user, email: "oauth_test@example.com")
      {:ok, user: user}
    end

    test "stores and retrieves sanbase:// URL through OAuth flow", %{conn: conn} do
      # Step 1: Initial OAuth request with sanbase:// URL
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> get("/auth/google", %{"success_redirect_url" => "sanbase://home"})

      # Verify the URL was stored in session
      assert get_session(conn, :__san_success_redirect_url) == "sanbase://home"
    end

    test "stores sanbase:// URL with path through OAuth flow", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> get("/auth/google", %{"success_redirect_url" => "sanbase://portfolio/btc"})

      assert get_session(conn, :__san_success_redirect_url) == "sanbase://portfolio/btc"
    end

    test "stores sanbase:// URL with query params through OAuth flow", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> get("/auth/google", %{
          "success_redirect_url" => "sanbase://home?tab=watchlist&asset=bitcoin"
        })

      assert get_session(conn, :__san_success_redirect_url) ==
               "sanbase://home?tab=watchlist&asset=bitcoin"
    end

    test "falls back to default when invalid URL is provided", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> get("/auth/google", %{"success_redirect_url" => "http://evil.com"})

      # Should fall back to website_url
      assert get_session(conn, :__san_success_redirect_url) ==
               SanbaseWeb.Endpoint.website_url()
    end

    test "accepts valid https URLs", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> get("/auth/google", %{"success_redirect_url" => "https://app-stage.santiment.net"})

      assert get_session(conn, :__san_success_redirect_url) == "https://app-stage.santiment.net"
    end

    test "includes JWT tokens in redirect URL when requested", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> get("/auth/google", %{
          "success_redirect_url" => "sanbase://home",
          "include_jwt_in_redirect_url" => "true"
        })

      assert get_session(conn, :__san_success_redirect_url) == "sanbase://home"
      assert get_session(conn, :__san_include_jwt_in_redirect_url) == true
    end

    test "does not include JWT tokens when not requested", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> get("/auth/google", %{"success_redirect_url" => "sanbase://home"})

      assert get_session(conn, :__san_success_redirect_url) == "sanbase://home"
      assert get_session(conn, :__san_include_jwt_in_redirect_url) == false
    end

    test "handles URL-encoded sanbase:// URLs", %{conn: conn} do
      # This is what actually happens in production!
      # The URL comes in as "sanbase%3A%2F%2Fauth%2F%3Fauth%3Dgoogle"
      encoded_url = "sanbase%3A%2F%2Fauth%2F%3Fauth%3Dgoogle"

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> get("/auth/google", %{"success_redirect_url" => encoded_url})

      # Should be decoded and stored as "sanbase://auth/?auth=google"
      assert get_session(conn, :__san_success_redirect_url) == "sanbase://auth/?auth=google"
    end

    test "handles URL-encoded sanbase:// URLs with path", %{conn: conn} do
      # sanbase://portfolio/btc encoded
      encoded_url = "sanbase%3A%2F%2Fportfolio%2Fbtc"

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> get("/auth/google", %{"success_redirect_url" => encoded_url})

      assert get_session(conn, :__san_success_redirect_url) == "sanbase://portfolio/btc"
    end

    test "handles HTTPS URLs with encoded query params", %{conn: conn} do
      # This tests that already-encoded query params don't break
      # URL with space encoded as %20
      url_with_encoded_space = "https://app.santiment.net/path?query=hello%20world"

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> get("/auth/google", %{"success_redirect_url" => url_with_encoded_space})

      stored_url = get_session(conn, :__san_success_redirect_url)

      # After URI.decode(), the %20 becomes a space
      assert stored_url == "https://app.santiment.net/path?query=hello world"
    end

    test "normal HTTPS URLs are not affected by decoding", %{conn: conn} do
      # Most common case - simple URLs should work exactly as before
      normal_url = "https://app-stage.santiment.net/dashboard"

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> get("/auth/google", %{"success_redirect_url" => normal_url})

      assert get_session(conn, :__san_success_redirect_url) == normal_url
    end
  end

  describe "validate_redirect_url/1" do
    test "accepts sanbase:// scheme with any path" do
      assert AuthController.validate_redirect_url("sanbase://home") == true
      assert AuthController.validate_redirect_url("sanbase://portfolio/btc") == true
      assert AuthController.validate_redirect_url("sanbase://settings") == true
      assert AuthController.validate_redirect_url("sanbase://login") == true
      assert AuthController.validate_redirect_url("sanbase://deep/nested/path") == true
    end

    test "accepts valid https santiment.net URLs" do
      assert AuthController.validate_redirect_url("https://santiment.net") == true
      assert AuthController.validate_redirect_url("https://app.santiment.net") == true
      assert AuthController.validate_redirect_url("https://app.santiment.net/dashboard") == true
      assert AuthController.validate_redirect_url("https://insights.santiment.net") == true
      assert AuthController.validate_redirect_url("https://queries.santiment.net") == true
      assert AuthController.validate_redirect_url("https://app-stage.santiment.net") == true
    end

    test "rejects invalid schemes" do
      assert AuthController.validate_redirect_url("http://santiment.net") ==
               {:error, "Invalid redirect URL"}

      assert AuthController.validate_redirect_url("ftp://santiment.net") ==
               {:error, "Invalid redirect URL"}

      assert AuthController.validate_redirect_url("mailto:test@santiment.net") ==
               {:error, "Invalid redirect URL"}
    end

    test "rejects invalid hosts" do
      assert AuthController.validate_redirect_url("https://example.com") ==
               {:error, "Invalid redirect URL"}

      assert AuthController.validate_redirect_url("https://malicious.net") ==
               {:error, "Invalid redirect URL"}

      assert AuthController.validate_redirect_url("https://santiment.com") ==
               {:error, "Invalid redirect URL"}
    end

    test "rejects malformed URLs" do
      assert AuthController.validate_redirect_url("not-a-url") ==
               {:error, "Invalid redirect URL"}

      assert AuthController.validate_redirect_url("//example.com") ==
               {:error, "Invalid redirect URL"}
    end
  end
end
