defmodule Sanbase.MCP.Server do
  @moduledoc "MCP server for Sanbase metrics access"

  use Anubis.Server,
    name: "sanbase-metrics",
    version: "1.0.0",
    capabilities: [:tools]

  @impl true
  def init(_client_info, %Anubis.Server.Frame{} = frame) do
    user = Sanbase.MCP.Auth.headers_list_to_user(frame.context.headers)
    frame = assign(frame, :current_user, user)
    {:ok, frame |> assign(:is_authenticated, not is_nil(user))}
  end

  @impl true
  def handle_request(request, %Anubis.Server.Frame{} = frame) do
    frame = assign_current_user(frame)
    Anubis.Server.Handlers.handle(request, __MODULE__, frame)
  end

  # Register our metrics tools
  component(Sanbase.MCP.MetricsAndAssetsDiscoveryTool)
  component(Sanbase.MCP.FetchMetricDataTool)

  # Register our insights tools
  component(Sanbase.MCP.InsightDiscoveryTool)
  component(Sanbase.MCP.FetchInsightsTool)

  # Register our social data tools
  component(Sanbase.MCP.TrendingStoriesTool)
  component(Sanbase.MCP.CombinedTrendsTool)

  # Register Screener tool
  component(Sanbase.MCP.AssetsByMetricTool)

  # Register Use Cases Catalog tool
  component(Sanbase.MCP.UseCasesCatalogTool)

  if Application.compile_env(:sanbase, :env) in [:test, :dev] do
    IO.puts("Defining the extra MCP Server tools used in dev and test")
    # Some tools are enabled only in dev mode so we can test things during development
    component(Sanbase.MCP.CheckAuthentication)
  end

  defp assign_current_user(%Anubis.Server.Frame{} = frame) do
    headers = frame.context.headers || %{}

    user =
      frame.assigns[:current_user] ||
        Sanbase.MCP.Auth.headers_list_to_user(headers)

    frame =
      if user do
        assign(frame, :current_user, user)
      else
        frame
      end

    assign(frame, :is_authenticated, not is_nil(user))
  end
end
