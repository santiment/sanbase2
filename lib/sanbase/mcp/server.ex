defmodule Sanbase.MCP.Server do
  @moduledoc """
  Core MCP server implementation that handles protocol-level functionality.

  This module implements the Model Context Protocol server specification,
  providing the necessary capabilities and server information.
  """

  require Logger

  @mcp_protocol_version "2025-03-26"
  @server_name "Sanbase MCP Server"
  @server_version "1.0.0"

  @doc """
  Returns the server capabilities according to MCP specification.

  Currently supports:
  - Tools: Functions that can be called by the MCP client
  """
  @spec get_capabilities() :: map()
  def get_capabilities do
    %{
      "tools" => %{
        "listChanged" => true
      }
    }
  end

  @doc """
  Returns server information for MCP protocol initialization.
  """
  @spec get_server_info() :: map()
  def get_server_info do
    %{
      "name" => @server_name,
      "version" => @server_version,
      "protocolVersion" => @mcp_protocol_version
    }
  end

  @doc """
  Handles MCP JSON-RPC requests and returns appropriate responses.
  """
  @spec handle_request(map()) :: {:ok, map()} | {:error, map()}
  def handle_request(%{"method" => "initialize", "params" => params} = request) do
    handle_initialize(request, params)
  end

  def handle_request(%{"method" => "tools/list"} = request) do
    handle_tools_list(request)
  end

  def handle_request(%{"method" => "tools/call", "params" => params} = request) do
    handle_tools_call(request, params)
  end

  def handle_request(%{"method" => method}) do
    Logger.warning("Unsupported MCP method: #{method}")

    {:error,
     %{
       "code" => -32601,
       "message" => "Method not found",
       "data" => %{"method" => method}
     }}
  end

  def handle_request(_invalid_request) do
    {:error,
     %{
       "code" => -32600,
       "message" => "Invalid Request"
     }}
  end

  # Private functions

  defp handle_initialize(request, params) do
    client_version = get_in(params, ["protocolVersion"])
    client_capabilities = get_in(params, ["capabilities"])

    Logger.info("MCP client connecting with protocol version: #{client_version}")
    Logger.debug("Client capabilities: #{inspect(client_capabilities)}")

    response = %{
      "jsonrpc" => "2.0",
      "id" => request["id"],
      "result" => %{
        "protocolVersion" => @mcp_protocol_version,
        "capabilities" => get_capabilities(),
        "serverInfo" => get_server_info()
      }
    }

    {:ok, response}
  end

  defp handle_tools_list(request) do
    tools = Sanbase.MCP.Tools.list_tools()

    response = %{
      "jsonrpc" => "2.0",
      "id" => request["id"],
      "result" => %{
        "tools" => tools
      }
    }

    {:ok, response}
  end

  defp handle_tools_call(request, %{"name" => tool_name, "arguments" => arguments}) do
    case Sanbase.MCP.Tools.call_tool(tool_name, arguments) do
      {:ok, result} ->
        response = %{
          "jsonrpc" => "2.0",
          "id" => request["id"],
          "result" => result
        }

        {:ok, response}

      {:error, reason} ->
        error_response = %{
          "jsonrpc" => "2.0",
          "id" => request["id"],
          "error" => %{
            "code" => -32000,
            "message" => "Tool execution failed",
            "data" => %{"reason" => to_string(reason)}
          }
        }

        {:error, error_response}
    end
  end

  defp handle_tools_call(request, _invalid_params) do
    error_response = %{
      "jsonrpc" => "2.0",
      "id" => request["id"],
      "error" => %{
        "code" => -32602,
        "message" => "Invalid params - missing name or arguments"
      }
    }

    {:error, error_response}
  end
end
