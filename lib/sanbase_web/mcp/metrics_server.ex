defmodule SanbaseWeb.MCP.MetricsServer do
  @moduledoc "MCP server for Sanbase metrics access"

  use Hermes.Server,
    name: "sanbase-metrics",
    version: "1.0.0",
    capabilities: [:tools]

  # Register our metrics tools
  component(SanbaseWeb.MCP.AvailableMetricsTool)
  component(SanbaseWeb.MCP.FetchMetricDataTool)
end
