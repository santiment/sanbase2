defmodule SanbaseWeb.Plug.RejectBrotliBodyEndpointTest do
  use SanbaseWeb.ConnCase, async: true

  test "the endpoint rejects a brotli-encoded GraphQL request before parsing it", %{conn: conn} do
    # Not valid brotli or JSON - the request must be rejected before any parser sees it.
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("content-encoding", "br")
      |> post("/graphql", "\x1b\x0b\x00\xf8garbage")

    assert response(conn, 415) =~ "Brotli"
  end
end
