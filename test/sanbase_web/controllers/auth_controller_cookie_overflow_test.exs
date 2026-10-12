defmodule SanbaseWeb.AuthControllerCookieOverflowTest do
  # SANBASE-BACKEND-PROD-8G3: long redirect/origin URLs overflowed the session cookie
  use SanbaseWeb.ConnCase, async: true

  @moduletag capture_log: true

  @app_url "https://app.santiment.net/charts?settings="

  for {name, headers, params} <- [
        {"a long Referer header", [{"referer", @app_url <> String.duplicate("a", 1_500)}], %{}},
        {"a long success_redirect_url", [],
         %{"success_redirect_url" => @app_url <> String.duplicate("a", 3_500)}},
        {"long success and fail redirect URLs", [],
         %{
           "success_redirect_url" => @app_url <> String.duplicate("a", 2_000),
           "fail_redirect_url" => @app_url <> String.duplicate("a", 2_000)
         }},
        {"redirect URLs under the limit and a Referer with long userinfo",
         [{"referer", "https://" <> String.duplicate("u", 900) <> "@app.santiment.net/"}],
         %{
           "success_redirect_url" => @app_url <> String.duplicate("a", 970),
           "fail_redirect_url" => @app_url <> String.duplicate("b", 970)
         }}
      ] do
    test "#{name} does not overflow the session cookie", %{conn: conn} do
      conn =
        Enum.reduce(unquote(headers), conn, fn {key, value}, conn ->
          put_req_header(conn, key, value)
        end)

      conn = get(conn, "/auth/google", unquote(Macro.escape(params)))

      assert conn.status == 302

      for {_name, %{value: value}} <- conn.resp_cookies do
        assert byte_size(value) <= 4096
      end
    end
  end

  test "long URLs do not overflow the session cookie of a logged in user", %{conn: conn} do
    user = Sanbase.Factory.insert(:user)
    {:ok, tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)

    conn =
      conn
      |> Plug.Test.init_test_session(tokens)
      |> put_req_header("referer", "https://" <> String.duplicate("h", 1_000) <> ".net/")
      |> get("/auth/google", %{
        "success_redirect_url" => @app_url <> String.duplicate("a", 970),
        "fail_redirect_url" => @app_url <> String.duplicate("b", 970)
      })

    assert conn.status == 302
    assert %{value: value} = conn.resp_cookies["_sanbase_sid"]
    assert byte_size(value) <= 4096
  end
end
