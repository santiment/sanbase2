defmodule Sanbase.Application.Mcp do
  def init() do
    :ok
  end

  def children() do
    children = [
      # MCP server for metrics access
      {Sanbase.MCP.Server, [transport: {:streamable_http, start: true}]},
      # Team-only MCP server for the knowledge base (FAQ, Academy, Insights)
      {Sanbase.MCP.Knowledge.Server, [transport: {:streamable_http, start: true}]},
      # Dev MCP server for search docs
      {Sanbase.MCP.DevServer, [transport: {:streamable_http, start: true}]}
    ]

    opts = [
      name: Sanbase.McpSupervisor,
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: 1
    ]

    {children, opts}
  end
end
