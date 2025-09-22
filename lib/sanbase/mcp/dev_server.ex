defmodule Sanbase.MCP.DevServer do
  @moduledoc "MCP dev server exposing search docs tool"

  use Anubis.Server,
    name: "sanbase-mcp-dev",
    version: "1.0.0",
    capabilities: [:tools]

  def init(_client_info, frame) do
    user = Sanbase.MCP.Auth.headers_list_to_user(frame.transport.req_headers)
    frame = if user, do: assign(frame, :current_user, user), else: frame
    {:ok, frame |> assign(:is_authenticated, not is_nil(user))}
  end

  # Expose only the search docs tool
  component(Sanbase.MCP.SearchDocsTool)
end
