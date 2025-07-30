defmodule Sanbase.Application.Mcp do
  import Sanbase.ApplicationUtils

  def init() do
    :ok
  end

  def children() do
    children = [
      # MCP server registry
      Hermes.Server.Registry,

      # MCP server for metrics access
      {Sanbase.MCP.MetricsServer, transport: :streamable_http}
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
