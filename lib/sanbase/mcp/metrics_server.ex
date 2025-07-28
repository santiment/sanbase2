defmodule Sanbase.MCP.MetricsServer do
  @moduledoc "MCP server for Sanbase metrics access"

  use Hermes.Server,
    name: "sanbase-metrics",
    version: "1.0.0",
    capabilities: [:tools]

  # Register our metrics tools
  component(Sanbase.MCP.DiscoveryTool)
  component(Sanbase.MCP.FetchMetricDataTool)
end
