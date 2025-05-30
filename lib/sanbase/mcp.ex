defmodule Sanbase.MCP do
  @moduledoc """
  The MCP context - provides Model Context Protocol server functionality.

  This context implements a simple MCP server that exposes tools to MCP clients.
  Currently supports a "say_hi" tool as an example.
  """

  alias Sanbase.MCP.Server
  alias Sanbase.MCP.Tools

  @doc """
  Handles a JSON-RPC 2.0 request and returns the appropriate response.
  """
  @spec handle_request(map() | list()) :: map() | list()
  def handle_request(request) when is_list(request) do
    # Handle batch requests
    Enum.map(request, &handle_single_request/1)
  end

  def handle_request(request) when is_map(request) do
    handle_single_request(request)
  end

  defp handle_single_request(%{"jsonrpc" => "2.0", "method" => method} = request) do
    id = Map.get(request, "id")
    params = Map.get(request, "params", %{})

    case method do
      "initialize" ->
        %{
          jsonrpc: "2.0",
          id: id,
          result: %{
            protocolVersion: "2025-03-26",
            capabilities: get_capabilities(),
            serverInfo: get_server_info()
          }
        }

      "tools/list" ->
        %{
          jsonrpc: "2.0",
          id: id,
          result: %{tools: list_tools()}
        }

      "tools/call" ->
        tool_name = Map.get(params, "name")
        arguments = Map.get(params, "arguments", %{})

        case call_tool(tool_name, arguments) do
          {:ok, result} ->
            %{
              jsonrpc: "2.0",
              id: id,
              result: result
            }

          {:error, reason} ->
            %{
              jsonrpc: "2.0",
              id: id,
              error: %{
                code: -32000,
                message: to_string(reason)
              }
            }
        end

      "notifications/initialized" ->
        # This is a notification, no response needed
        nil

      _ ->
        %{
          jsonrpc: "2.0",
          id: id,
          error: %{
            code: -32601,
            message: "Method not found"
          }
        }
    end
  end

  defp handle_single_request(_invalid_request) do
    %{
      jsonrpc: "2.0",
      id: nil,
      error: %{
        code: -32600,
        message: "Invalid Request"
      }
    }
  end

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
