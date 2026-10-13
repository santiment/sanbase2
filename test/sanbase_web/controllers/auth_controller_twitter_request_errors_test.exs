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
         {:error, %HTTPoison.Error{reason: :checkout_timeout, id: nil}}},
        {"a Twitter API error",
         {:ok,
          %HTTPoison.Response{
            status_code: 401,
            body: %{"errors" => [%{"message" => "Could not authenticate you.", "code" => 32}]}
          }}},
        {"an unknown error", {:error, :econnrefused}}
      ] do
    test "#{name} redirects to the fail URL", %{conn: conn} do
      with_mock Ueberauth.Strategy.Twitter.OAuth.Internal,
        get: fn _url, _params, _consumer -> unquote(Macro.escape(response)) end do
        conn = get(conn, "/auth/twitter", %{"fail_redirect_url" => @fail_redirect_url})

        assert redirected_to(conn, 302) == @fail_redirect_url
      end
    end
  end

  test "a request token redirects to Twitter's authorize URL", %{conn: conn} do
    body = "oauth_token=token123&oauth_token_secret=secret&oauth_callback_confirmed=true"

    with_mock Ueberauth.Strategy.Twitter.OAuth.Internal, [:passthrough],
      get: fn _url, _params, _consumer ->
        {:ok, %HTTPoison.Response{status_code: 200, body: body}}
      end do
      conn = get(conn, "/auth/twitter", %{"fail_redirect_url" => @fail_redirect_url})

      assert redirected_to(conn, 302) =~ "oauth_token=token123"
      assert get_session(conn, :twitter_token)
    end
  end
end
