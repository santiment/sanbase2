defmodule SanbaseWeb.Plug.RejectCompressedBodyEndpointTest do
  use SanbaseWeb.ConnCase, async: true

  for coding <- ["br", "gzip"] do
    test "the endpoint rejects a #{coding}-encoded GraphQL request before parsing it",
         %{conn: conn} do
      # Not valid compressed data or JSON - the request must be rejected before any
      # parser sees it.
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("content-encoding", unquote(coding))
        |> post("/graphql", "\x1b\x0b\x00\xf8garbage")

      assert response(conn, 415) =~ "Compressed request bodies are not supported"
    end
  end

  test "a bogus content-encoding with a plain JSON body still works", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("content-encoding", "utf-8")
      |> post("/graphql", Jason.encode!(%{query: "{ __typename }"}))

    assert json_response(conn, 200) == %{"data" => %{"__typename" => "RootQueryType"}}
  end
end
