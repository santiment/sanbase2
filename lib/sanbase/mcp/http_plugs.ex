defmodule Sanbase.MCP.StreamableHTTPPlug do
  @moduledoc "Wrapper plug to expose Sanbase.MCP.Server via forward"
  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    Anubis.Server.Transport.StreamableHTTP.Plug.call(
      conn,
      Anubis.Server.Transport.StreamableHTTP.Plug.init(server: Sanbase.MCP.Server)
    )
  end
end

defmodule Sanbase.MCP.StreamableHTTPDevPlug do
  @moduledoc "Wrapper plug to expose Sanbase.MCP.DevServer via forward"
  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    Anubis.Server.Transport.StreamableHTTP.Plug.call(
      conn,
      Anubis.Server.Transport.StreamableHTTP.Plug.init(server: Sanbase.MCP.DevServer)
    )
  end
end
