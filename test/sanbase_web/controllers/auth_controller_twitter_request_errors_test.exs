defmodule SanbaseWeb.AuthControllerTwitterRequestErrorsTest do
  # Reproduces:
  #   SANBASE-BACKEND-PROD-CZN - ArgumentError: raise/1 ... got: {:ok, %HTTPoison.Response{status_code: 503, ...}}
  #   SANBASE-BACKEND-PROD-CZM - RuntimeError: checkout_timeout
  #
  # Sanbase.Ueberauth.Strategy.Twitter.handle_request!/1 calls the bang function
  # Ueberauth.Strategy.Twitter.OAuth.request_token!/2, which `raise`s whatever
  # request_token/2 returns as error:
  #   * a non-200 response from Twitter (e.g. 503) becomes `{:error, {:ok, %HTTPoison.Response{}}}`
  #     and `raise {:ok, ...}` is itself an ArgumentError;
  #   * a transport error becomes `{:error, "checkout_timeout"}` -> RuntimeError.
  # Either way GET /auth/twitter crashes with a 500 instead of sending the user back to
  # the fail redirect URL.
  #
  # Mock is global (meck), so this module is not async.
  use SanbaseWeb.ConnCase, async: false

  import Mock

  @moduletag capture_log: true

  @fail_redirect_url "https://app.santiment.net/login-failed"

  @twitter_503 {:ok,
                %HTTPoison.Response{
                  status_code: 503,
                  body: "<!DOCTYPE html><html><title>X / Error</title></html>",
                  headers: [{"Content-Type", "text/html;charset=utf-8"}],
                  request_url: "https://api.twitter.com/oauth/request_token"
                }}

  @checkout_timeout {:error, %HTTPoison.Error{reason: :checkout_timeout, id: nil}}

  test "Twitter responding with 503 redirects to the fail URL instead of crashing", %{conn: conn} do
    with_mock Ueberauth.Strategy.Twitter.OAuth.Internal,
      get: fn _url, _params, _consumer -> @twitter_503 end do
      conn = get(conn, "/auth/twitter", %{"fail_redirect_url" => @fail_redirect_url})

      assert redirected_to(conn, 302) == @fail_redirect_url
    end
  end

  test "HTTP pool checkout_timeout redirects to the fail URL instead of crashing", %{conn: conn} do
    with_mock Ueberauth.Strategy.Twitter.OAuth.Internal,
      get: fn _url, _params, _consumer -> @checkout_timeout end do
      conn = get(conn, "/auth/twitter", %{"fail_redirect_url" => @fail_redirect_url})

      assert redirected_to(conn, 302) == @fail_redirect_url
    end
  end
end
