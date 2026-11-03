defmodule SanbaseWeb.Plug.RejectCompressedBodyTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias SanbaseWeb.Plug.RejectCompressedBody

  defp call(headers) do
    conn =
      Enum.reduce(headers, conn(:post, "/graphql", "body"), fn {k, v}, conn ->
        put_req_header(conn, k, v)
      end)

    RejectCompressedBody.call(conn, RejectCompressedBody.init([]))
  end

  test "rejects a compressed body with 415 and advertises identity" do
    conn = call([{"content-encoding", "br"}])

    assert conn.halted
    assert conn.status == 415
    assert get_resp_header(conn, "accept-encoding") == ["identity"]
  end

  test "rejects every known compression coding" do
    for coding <- ~w(br gzip x-gzip deflate compress x-compress zstd dcb dcz) do
      conn = call([{"content-encoding", coding}])

      assert conn.halted, "expected #{coding} to be rejected"
      assert conn.status == 415
    end
  end

  test "rejects a compression coding inside a list, case-insensitively" do
    for value <- ["identity, BR", " Gzip ", "identity,zstd"] do
      conn = call([{"content-encoding", value}])

      assert conn.halted, "expected #{inspect(value)} to be rejected"
      assert conn.status == 415
    end
  end

  test "passes requests without content-encoding through" do
    conn = call([])

    refute conn.halted
    assert conn.status == nil
  end

  test "passes identity and unknown content-encodings through" do
    # `utf-8` is a bogus value some clients send with a plain body - it works today.
    for value <- ["identity", "utf-8", "UTF-8", "brotli-ish", ""] do
      conn = call([{"content-encoding", value}])

      refute conn.halted, "expected #{inspect(value)} to pass"
    end
  end
end
