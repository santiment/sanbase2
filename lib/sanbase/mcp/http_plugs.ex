defmodule Sanbase.MCP.StreamableHTTPPlug do
  @moduledoc "Wrapper plug to expose Sanbase.MCP.Server via forward"
  use Plug.Builder
  plug Anubis.Server.Transport.StreamableHTTP.Plug, server: Sanbase.MCP.Server
end

defmodule Sanbase.MCP.StreamableHTTPDevPlug do
  @moduledoc "Wrapper plug to expose Sanbase.MCP.DevServer via forward"
  use Plug.Builder
  plug Anubis.Server.Transport.StreamableHTTP.Plug, server: Sanbase.MCP.DevServer
end
