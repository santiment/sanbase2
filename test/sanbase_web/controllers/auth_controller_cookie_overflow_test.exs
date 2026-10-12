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
end
