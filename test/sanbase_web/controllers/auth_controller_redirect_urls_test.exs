defmodule SanbaseWeb.AuthControllerRedirectUrlsTest do
  # The redirect and origin URLs the OAuth request stores, and where the callback sends the user
  use SanbaseWeb.ConnCase, async: false

  @moduletag capture_log: true

  @success_url "https://app.santiment.net/charts"
  @fail_url "https://app.santiment.net/login"
  @long_success_url "https://app.santiment.net/charts?settings=" <> String.duplicate("a", 970)
  @long_fail_url "https://app.santiment.net/charts?settings=" <> String.duplicate("b", 970)

  describe "request/2 session URLs" do
    test "stores a fail URL that differs from the success URL", %{conn: conn} do
      conn =
        request(conn, %{"success_redirect_url" => @success_url, "fail_redirect_url" => @fail_url})

      assert get_session(conn, :__san_success_redirect_url) == @success_url
      assert get_session(conn, :__san_fail_redirect_url) == @fail_url
    end

    test "does not store a fail URL equal to the success URL", %{conn: conn} do
      conn =
        request(conn, %{
          "success_redirect_url" => @success_url,
          "fail_redirect_url" => @success_url
        })

      assert get_session(conn, :__san_success_redirect_url) == @success_url
      assert get_session(conn, :__san_fail_redirect_url) == nil
    end

    test "keeps only the scheme, host and port of the Referer as the origin", %{conn: conn} do
      conn =
        conn
        |> put_req_header("referer", "https://user:secret@app.santiment.net:8443/x?y=1#z")
        |> request(%{"success_redirect_url" => @success_url})

      assert get_session(conn, :__san_origin_url) == "https://app.santiment.net:8443"
    end

    test "over the budget, the fail URL falls back to the success URL", %{conn: conn} do
      conn =
        conn
        |> put_req_header("referer", "https://app.santiment.net/")
        |> request(%{
          "success_redirect_url" => @long_success_url,
          "fail_redirect_url" => @long_fail_url
        })

      assert get_session(conn, :__san_success_redirect_url) == @long_success_url
      assert get_session(conn, :__san_fail_redirect_url) == nil
      assert get_session(conn, :__san_origin_url) == "https://app.santiment.net"
    end

    test "over the budget, the origin falls back to the website URL", %{conn: conn} do
      conn =
        conn
        |> put_req_header("referer", "https://" <> String.duplicate("h", 1_000) <> ".net/")
        |> request(%{"success_redirect_url" => @long_success_url})

      assert get_session(conn, :__san_success_redirect_url) == @long_success_url
      assert get_session(conn, :__san_origin_url) == SanbaseWeb.Endpoint.website_url()
    end
  end

  describe "callback/2 redirects" do
    for provider <- ["google", "twitter"] do
      test "#{provider}: a successful login redirects to the success URL", %{conn: conn} do
        conn =
          conn
          |> Plug.Test.init_test_session(%{
            __san_success_redirect_url: @success_url,
            __san_fail_redirect_url: @fail_url
          })
          |> callback(unquote(provider))

        assert redirected_to(conn) == @success_url <> "?signup=true"
        assert get_session(conn, :access_token)
      end

      test "#{provider}: a failed login redirects to the fail URL", %{conn: conn} do
        conn =
          conn
          |> Plug.Test.init_test_session(%{
            __san_success_redirect_url: @success_url,
            __san_fail_redirect_url: @fail_url
          })
          |> callback(unquote(provider), fail_login?: true)

        assert redirected_to(conn) == @fail_url
      end

      test "#{provider}: a failed login without a fail URL redirects to the success URL",
           %{conn: conn} do
        conn =
          conn
          |> Plug.Test.init_test_session(%{__san_success_redirect_url: @success_url})
          |> callback(unquote(provider), fail_login?: true)

        assert redirected_to(conn) == @success_url
      end

      test "#{provider}: a failed login without any URL redirects to the website",
           %{conn: conn} do
        conn =
          conn
          |> Plug.Test.init_test_session(%{})
          |> callback(unquote(provider), fail_login?: true)

        assert redirected_to(conn) == SanbaseWeb.Endpoint.website_url()
      end
    end
  end

  defp request(conn, params), do: get(conn, "/auth/google", params)

  # Ueberauth.run_callback/3 is mocked, so the provider is never contacted. A failed login
  # is a failing step after the provider returned the user.
  defp callback(conn, provider, opts \\ []) do
    auth = %Ueberauth.Auth{
      uid: "twitter-#{System.unique_integer([:positive])}",
      info: %Ueberauth.Auth.Info{email: "user#{System.unique_integer([:positive])}@santiment.net"}
    }

    mocks =
      Sanbase.Mock.prepare_mock(Ueberauth, :run_callback, fn conn, _provider, _config ->
        Plug.Conn.assign(conn, :ueberauth_auth, auth)
      end)

    mocks =
      if Keyword.get(opts, :fail_login?, false),
        do:
          Sanbase.Mock.prepare_mock2(
            mocks,
            &Sanbase.Accounts.forward_registration/3,
            {:error, "boom"}
          ),
        else: mocks

    Sanbase.Mock.run_with_mocks(mocks, fn -> get(conn, "/auth/#{provider}/callback") end)
  end
end
