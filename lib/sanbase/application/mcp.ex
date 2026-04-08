defmodule Sanbase.Application.Mcp do
  import Sanbase.ApplicationUtils

  def init() do
    :ok
  end

  def children() do
    registry = {Sanbase.MCP.Registry.Pg, []}

    children = [
      # Join the libcluster Postgres topology so MCP pods form a BEAM cluster.
      # This enables distributed :pg session lookup across pods.
      start_in(
        {Cluster.Supervisor,
         [
           Application.get_env(:libcluster, :topologies),
           [name: Sanbase.ClusterSupervisor]
         ]},
        [:dev, :prod]
      ),

      # Start :pg scope for distributed session registry.
      # Must be started before the MCP servers that use it.
      %{
        id: Sanbase.MCP.Registry.Pg,
        start: {:pg, :start_link, [Sanbase.MCP.Registry.Pg.scope()]}
      },

      # MCP server for metrics access
      {Sanbase.MCP.Server, [transport: {:streamable_http, start: true}, registry: registry]},
      # Dev MCP server for search docs
      {Sanbase.MCP.DevServer, [transport: {:streamable_http, start: true}, registry: registry]}
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
