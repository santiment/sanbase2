defmodule SanbaseWeb.MCPController do
  use SanbaseWeb, :controller

  require Logger

  @doc """
  Handles MCP JSON-RPC requests over HTTP.

  This endpoint receives JSON-RPC 2.0 requests and delegates them to the MCP server.
  It supports both single requests and batch requests as per JSON-RPC specification.
  """
  def handle(conn, params) do
    # Try to get JSON from parsed params first, then from raw body
    with {:ok, json_request} <- get_json_request(conn, params),
         {:ok, response} <- process_request(json_request) do
      conn
      |> put_resp_content_type("application/json")
      |> json(response)
    else
      {:error, :invalid_json} ->
        error_response = %{
          "jsonrpc" => "2.0",
          "error" => %{
            "code" => -32700,
            "message" => "Parse error"
          },
          "id" => nil
        }

        conn
        |> put_status(:bad_request)
        |> put_resp_content_type("application/json")
        |> json(error_response)

      {:error, reason} ->
        Logger.error("MCP request processing failed: #{inspect(reason)}")

        error_response = %{
          "jsonrpc" => "2.0",
          "error" => %{
            "code" => -32603,
            "message" => "Internal error"
          },
          "id" => nil
        }

        conn
        |> put_status(:internal_server_error)
        |> put_resp_content_type("application/json")
        |> json(error_response)
    end
  end

  # Private functions

  defp get_json_request(conn, params) do
    cond do
      # If params are not empty and contain MCP-like structure, use them
      not Enum.empty?(params) and (Map.has_key?(params, "jsonrpc") or is_list(params)) ->
        {:ok, params}

      # Otherwise, try to read raw body
      true ->
        case read_request_body(conn) do
          {:ok, body} when body != "" ->
            case Jason.decode(body) do
              {:ok, json_request} -> {:ok, json_request}
              {:error, _} -> {:error, :invalid_json}
            end

          {:ok, ""} ->
            {:error, :invalid_json}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp read_request_body(conn) do
    case Plug.Conn.read_body(conn) do
      {:ok, body, _conn} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end

  defp process_request(json_request) when is_list(json_request) do
    # Handle batch requests
    responses =
      json_request
      |> Enum.map(&process_single_request/1)
      |> Enum.filter(fn response -> response != :notification end)

    case responses do
      # All were notifications
      [] -> {:ok, %{}}
      _ -> {:ok, responses}
    end
  end

  defp process_request(json_request) when is_map(json_request) do
    # Handle single request
    case process_single_request(json_request) do
      :notification -> {:ok, %{}}
      response -> {:ok, response}
    end
  end

  defp process_request(_invalid) do
    {:error, :invalid_request}
  end

  defp process_single_request(%{"jsonrpc" => "2.0"} = request) do
    # Check if this is a notification (no id field)
    case Map.has_key?(request, "id") do
      true ->
        # Regular request - process and return response
        case Sanbase.MCP.Server.handle_request(request) do
          {:ok, response} -> response
          {:error, error_response} -> error_response
        end

      false ->
        # Notification - process but don't return response
        case Map.get(request, "method") do
          "initialized" ->
            Logger.info("MCP client initialization completed")
            :notification

          method ->
            Logger.debug("Received MCP notification: #{method}")
            :notification
        end
    end
  end

  defp process_single_request(invalid_request) do
    Logger.warning("Invalid JSON-RPC request: #{inspect(invalid_request)}")

    %{
      "jsonrpc" => "2.0",
      "error" => %{
        "code" => -32600,
        "message" => "Invalid Request"
      },
      "id" => Map.get(invalid_request, "id")
    }
  end
end
