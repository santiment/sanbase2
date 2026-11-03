defmodule SanbaseWeb.Plug.RejectBrotliBody do
  @moduledoc ~s"""
  Explicitly reject requests whose body is Brotli-compressed (`Content-Encoding: br`).

  Nothing in our stack decodes Brotli request bodies: Cowboy's decompress stream handler
  is not enabled and Plug.Parsers ignores `Content-Encoding`. Without this plug such a
  body is either fed raw to the JSON/multipart parsers (a confusing 400 parse error) or,
  because Plug.Parsers is configured with `pass: ["*/*"]`, passed through unparsed to the
  controllers.

  Per RFC 9110, section 8.4.1, a server that does not support the content coding of a
  request responds with `415 Unsupported Media Type` and may list the codings it does
  accept in the `Accept-Encoding` response header.

  This plug only inspects request headers, so it is safe to run before the body is read.
  It must be placed before any plug that reads the body (Plug.Parsers,
  SanbaseWeb.Plug.VerifyStripeWebhook).
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if brotli_encoded?(conn) do
      conn
      |> put_resp_header("accept-encoding", "identity")
      |> send_resp(:unsupported_media_type, "Brotli-compressed request bodies are not supported")
      |> halt()
    else
      conn
    end
  end

  # Content-Encoding is a comma-separated list (e.g. "gzip, br") and can be split across
  # multiple header lines. Codings are case-insensitive.
  defp brotli_encoded?(conn) do
    conn
    |> get_req_header("content-encoding")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.any?(&(&1 |> String.trim() |> String.downcase() == "br"))
  end
end
