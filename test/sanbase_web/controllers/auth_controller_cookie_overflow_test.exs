defmodule SanbaseWeb.AuthControllerCookieOverflowTest do
  # Reproduces SANBASE-BACKEND-PROD-8G3:
  # Plug.Conn.CookieOverflowError: cookie named "_sanbase_sid" exceeds maximum size of 4096 bytes
  #
  # AuthController.request/2 stores the success/fail redirect URLs and the origin URL in
  # the cookie session. The redirect URLs may be up to 4096 bytes each
  # (@max_redirect_url_length) and the origin URL (derived from the Referer header,
  # keeping its query string) is not length-checked at all. The same long URL ends up
  # in the session 2-3 times, the signed cookie exceeds 4096 bytes and the request
  # crashes with a 500 when the response is sent.
  #
  # The requests go through the real endpoint session plug (no init_test_session) so
  # the cookie is serialized exactly as in production.
  use SanbaseWeb.ConnCase, async: true

  @moduletag capture_log: true

  # A valid, allowed redirect URL - a chart page with a long settings query string.
  defp long_app_url(query_size) do
    "https://app.santiment.net/charts?settings=" <> String.duplicate("a", query_size)
  end

  test "a long Referer header does not overflow the session cookie", %{conn: conn} do
    conn =
      conn
      |> put_req_header("referer", long_app_url(1_500))
      |> get("/auth/google")

    assert conn.status == 302
    assert_cookie_fits(conn)
  end

  test "a long success_redirect_url does not overflow the session cookie", %{conn: conn} do
    conn = get(conn, "/auth/google", %{"success_redirect_url" => long_app_url(3_500)})

    assert conn.status == 302
    assert_cookie_fits(conn)
  end

  test "long success and fail redirect URLs do not overflow the session cookie", %{conn: conn} do
    url = long_app_url(2_000)

    conn =
      get(conn, "/auth/google", %{
        "success_redirect_url" => url,
        "fail_redirect_url" => url
      })

    assert conn.status == 302
    assert_cookie_fits(conn)
  end

  defp assert_cookie_fits(conn) do
    for {_name, %{value: value}} <- conn.resp_cookies do
      assert byte_size(value) <= 4096
    end
  end
end
