defmodule Sanbase.MCP.Dev.StreamableHTTPPlug do
  @moduledoc "Wrapper plug to expose Sanbase.MCP.Dev.Server via forward"
  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn = Sanbase.MCP.StreamableHTTPPlug.normalize_post_accept_header(conn)

    Anubis.Server.Transport.StreamableHTTP.Plug.call(
      conn,
      Anubis.Server.Transport.StreamableHTTP.Plug.init(
        server: Sanbase.MCP.Dev.Server,
        request_timeout: 150_000
      )
    )
  end
end
