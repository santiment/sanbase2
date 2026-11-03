defmodule SanbaseWeb.Plug.RejectCompressedBody do
  @moduledoc ~s"""
  Reject requests with a compressed body (`Content-Encoding: br`, `gzip`, ...) with
  `415`, since nothing in our stack decodes them. Unknown values (e.g. a bogus
  `utf-8`) pass through unchanged.

  Only inspects headers, so it must run before any plug that reads the body
  (Plug.Parsers, SanbaseWeb.Plug.VerifyStripeWebhook).
  """
  @behaviour Plug

  import Plug.Conn

  # IANA HTTP Content Coding Registry, without `identity` (no transformation).
  @compression_codings ~w(br gzip x-gzip deflate compress x-compress zstd dcb dcz)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if compressed?(conn) do
      conn
      |> put_resp_header("accept-encoding", "identity")
      |> send_resp(:unsupported_media_type, "Compressed request bodies are not supported")
      |> halt()
    else
      conn
    end
  end

  # Content-Encoding is a comma-separated list (e.g. "gzip, br") and can be split across
  # multiple header lines. Codings are case-insensitive.
  defp compressed?(conn) do
    conn
    |> get_req_header("content-encoding")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.any?(&((&1 |> String.trim() |> String.downcase()) in @compression_codings))
  end
end
