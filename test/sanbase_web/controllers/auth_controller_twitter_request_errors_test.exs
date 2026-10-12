defmodule SanbaseWeb.AuthControllerTwitterRequestErrorsTest do
  # SANBASE-BACKEND-PROD-CZN / CZM: request token errors crashed GET /auth/twitter
  use SanbaseWeb.ConnCase, async: false

  import Mock

  @moduletag capture_log: true

  @fail_redirect_url "https://app.santiment.net/login-failed"

  for {name, response} <- [
        {"a 503 response",
         {:ok,
          %HTTPoison.Response{
            status_code: 503,
            body: "<!DOCTYPE html><html><title>X / Error</title></html>",
            headers: [{"Content-Type", "text/html;charset=utf-8"}],
            request_url: "https://api.twitter.com/oauth/request_token"
          }}},
        {"an HTTP pool checkout_timeout",
         {:error, %HTTPoison.Error{reason: :checkout_timeout, id: nil}}}
      ] do
    test "#{name} redirects to the fail URL", %{conn: conn} do
      with_mock Ueberauth.Strategy.Twitter.OAuth.Internal,
        get: fn _url, _params, _consumer -> unquote(Macro.escape(response)) end do
        conn = get(conn, "/auth/twitter", %{"fail_redirect_url" => @fail_redirect_url})

        assert redirected_to(conn, 302) == @fail_redirect_url
      end
    end
  end
end
