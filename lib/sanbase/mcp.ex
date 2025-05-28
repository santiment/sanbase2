defmodule Sanbase.MCP do
  @moduledoc """
  The MCP context - provides Model Context Protocol server functionality.

  This context implements a simple MCP server that exposes tools to MCP clients.
  Currently supports a "say_hi" tool as an example.
  """

  alias Sanbase.MCP.Server
  alias Sanbase.MCP.Tools

  @doc """
  Lists all available tools that this MCP server exposes.
  """
  @spec list_tools() :: list(map())
  def list_tools do
    Tools.list_tools()
  end

  @doc """
  Calls a specific tool with the given arguments.
  """
  @spec call_tool(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def call_tool(name, arguments) do
    Tools.call_tool(name, arguments)
  end

  @doc """
  Gets the server capabilities that this MCP server supports.
  """
  @spec get_capabilities() :: map()
  def get_capabilities do
    Server.get_capabilities()
  end

  @doc """
  Gets server information for MCP protocol initialization.
  """
  @spec get_server_info() :: map()
  def get_server_info do
    Server.get_server_info()
  end
end
