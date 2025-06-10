defmodule Sanbase.McpServer do
  @moduledoc """
  Main MCP server multiplexer for Sanbase.

  This server acts as a multiplexer that delegates to specific
  servers based on the tool being called.
  """
  use Toolmux.Server

  alias SanbaseWeb.McpServers.TrendingWordsServer

  @impl true
  def server_info() do
    %{
      name: "Sanbase MCP Server",
      version: "1.0.0",
      description: "Main MCP server for Sanbase crypto data access",
      capabilities: %{
        tools: %{}
      }
    }
  end

  @impl true
  def list_tools() do
    TrendingWordsServer.list_tools()
  end

  @impl true
  def call_tool(tool_name, params) do
    case tool_name do
      tool when tool in ["get_trending_words"] ->
        TrendingWordsServer.call_tool(tool_name, params)

      _ ->
        {:error, "Unknown tool: #{tool_name}"}
    end
  end
end
