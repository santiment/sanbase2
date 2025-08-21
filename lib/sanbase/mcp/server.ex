defmodule Sanbase.MCP.Server do
  @moduledoc "MCP server for Sanbase metrics access"

  use Hermes.Server,
    name: "sanbase-metrics",
    version: "1.0.0",
    capabilities: [:tools]

  def init(_client_info, frame) do
    user = Sanbase.MCP.Auth.headers_list_to_user(frame.transport.req_headers)
    frame = if user, do: assign(frame, :current_user, user), else: frame
    {:ok, frame |> assign(:is_authenticated, not is_nil(user))}
  end

  # Register our metrics tools
  component(Sanbase.MCP.MetricsAndAssetsDiscoveryTool)
  component(Sanbase.MCP.FetchMetricDataTool)

  # Register our insights tools
  component(Sanbase.MCP.InsightDiscoveryTool)
  component(Sanbase.MCP.InsightDetailTool)

  if Application.compile_env(:sanbase, :env) in [:test, :dev] do
    IO.puts("Defining the extra MCP Server tools used in dev and test")
    # Some tools are enabled only in dev mode so we can test things during development
    component(Sanbase.MCP.CheckAuthentication)
  end
end
