defmodule SanbaseWeb.AuthControllerRedirectUrlsTest do
  use SanbaseWeb.ConnCase, async: false

  @moduletag capture_log: true

  @success_url "https://app.santiment.net/charts"
  @fail_url "https://app.santiment.net/login"
  @app_url "https://app.santiment.net/charts?settings="

  for provider <- ["google", "twitter"] do
    test "#{provider}: a successful login redirects to the success URL", %{conn: conn} do
      conn =
        conn
        |> request("google", %{"success_redirect_url" => @success_url})
        |> callback(unquote(provider))

      assert redirected_to(conn) == @success_url <> "?signup=true"
      assert get_session(conn, :access_token)
    end

    test "#{provider}: a failed login redirects to the fail URL", %{conn: conn} do
      conn =
        conn
        |> request("google", %{
          "success_redirect_url" => @success_url,
          "fail_redirect_url" => @fail_url
        })
        |> callback(unquote(provider), fail_login?: true)

      assert redirected_to(conn) == @fail_url
    end
  end

  test "a failed login with the same success and fail URL redirects to it", %{conn: conn} do
    conn =
      conn
      |> request("google", %{
        "success_redirect_url" => @success_url,
        "fail_redirect_url" => @success_url
      })
      |> callback("google", fail_login?: true)

    assert redirected_to(conn) == @success_url
  end

  test "a failed login without any URL redirects to the website", %{conn: conn} do
    conn =
      conn
      |> request("google", %{})
      |> callback("google", fail_login?: true)

    assert redirected_to(conn) == SanbaseWeb.Endpoint.website_url()
  end

  test "oversized redirect URLs do not overflow the session cookie", %{conn: conn} do
    conn
    |> put_req_header("referer", "https://" <> String.duplicate("u", 900) <> "@app.net/")
    |> request("google", %{
      "success_redirect_url" => @app_url <> String.duplicate("a", 2_000),
      "fail_redirect_url" => @app_url <> String.duplicate("b", 2_000)
    })
  end

  test "long URLs of a logged in user fit the session cookie and keep the success URL",
       %{conn: conn} do
    user = Sanbase.Factory.insert(:user)
    {:ok, tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)
    success_url = @app_url <> String.duplicate("a", 970)

    conn =
      conn
      |> Plug.Test.init_test_session(tokens)
      |> put_req_header("referer", "https://" <> String.duplicate("h", 1_000) <> ".net/")
      |> request("google", %{
        "success_redirect_url" => success_url,
        "fail_redirect_url" => @app_url <> String.duplicate("b", 970)
      })
      |> callback("google")

    assert redirected_to(conn) == success_url <> "&signup=true"
  end

  # Runs the request phase and carries its session cookie over to the next request
  defp request(conn, provider, params) do
    conn = get(conn, "/auth/#{provider}", params)

    assert conn.status == 302

    for {_name, %{value: value}} <- conn.resp_cookies do
      assert byte_size(value) <= 4096
    end

    recycle(conn)
  end

  # The provider is never contacted. A failed login is a failing step after it returned the user.
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
