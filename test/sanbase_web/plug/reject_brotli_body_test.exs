defmodule SanbaseWeb.Plug.RejectBrotliBodyTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias SanbaseWeb.Plug.RejectBrotliBody

  defp call(headers) do
    conn =
      Enum.reduce(headers, conn(:post, "/graphql", "body"), fn {k, v}, conn ->
        put_req_header(conn, k, v)
      end)

    RejectBrotliBody.call(conn, RejectBrotliBody.init([]))
  end

  test "rejects a brotli-encoded body with 415" do
    conn = call([{"content-encoding", "br"}])

    assert conn.halted
    assert conn.status == 415
    assert get_resp_header(conn, "accept-encoding") == ["identity"]
  end

  test "rejects brotli inside a coding list, case-insensitively" do
    conn = call([{"content-encoding", "gzip, BR"}])

    assert conn.halted
    assert conn.status == 415
  end

  test "passes requests without content-encoding through" do
    conn = call([])

    refute conn.halted
    assert conn.status == nil
  end

  test "passes non-brotli content-encodings through" do
    for encoding <- ["gzip", "identity", "deflate", "brotli-ish"] do
      conn = call([{"content-encoding", encoding}])

      refute conn.halted, "expected #{encoding} to pass"
    end
  end
end
