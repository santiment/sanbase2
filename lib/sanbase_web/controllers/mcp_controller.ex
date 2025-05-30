defmodule SanbaseWeb.MCPController do
  use SanbaseWeb, :controller

  require Logger

  alias Sanbase.MCP

  @session_id_header "mcp-session-id"

  @doc """
  Handles MCP JSON-RPC requests over HTTP.

  This endpoint receives JSON-RPC 2.0 requests and delegates them to the MCP server.
  It supports both single requests and batch requests as per JSON-RPC specification.
  """
  def handle(conn, params) do
    Logger.info("MCP request received")
    Logger.info("Request params: #{inspect(params)}")
    Logger.info("Request body_params: #{inspect(conn.body_params)}")

    # Try to get JSON data from parsed body_params first, then raw body
    json_data =
      cond do
        not Enum.empty?(conn.body_params) ->
          Logger.info("Using parsed body_params")
          conn.body_params

        not Enum.empty?(params) and (Map.has_key?(params, "jsonrpc") or is_list(params)) ->
          Logger.info("Using request params")
          params

        true ->
          Logger.info("Reading raw body")

          case Plug.Conn.read_body(conn) do
            {:ok, body, _conn} when body != "" ->
              case Jason.decode(body) do
                {:ok, decoded} ->
                  decoded

                {:error, reason} ->
                  Logger.error("JSON decode failed: #{inspect(reason)}")
                  :parse_error
              end

            {:ok, _empty_body, _conn} ->
              Logger.error("Empty body")
              :empty_body

            {:error, reason} ->
              Logger.error("Read body failed: #{inspect(reason)}")
              :read_error
          end
      end

    case json_data do
      data when data in [:parse_error, :empty_body, :read_error] ->
        error_response = %{
          jsonrpc: "2.0",
          error: %{
            code: -32700,
            message: "Parse error"
          },
          id: nil
        }

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(error_response))

      json_data ->
        Logger.info("Successfully parsed JSON: #{inspect(json_data)}")
        session_id = get_req_header(conn, @session_id_header) |> List.first()

        response = MCP.handle_request(json_data)
        Logger.info("MCP response: #{inspect(response)}")

        # For initialization requests, include session ID in response header
        if is_initialize_request?(json_data) do
          new_session_id = generate_session_id()
          Logger.info("Initialization request - generated session ID: #{new_session_id}")

          conn
          |> put_resp_header(@session_id_header, new_session_id)
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(response))
        else
          # For existing sessions, validate session ID
          if session_id do
            # Filter out nil responses (from notifications)
            filtered_response =
              if is_list(response) do
                Enum.filter(response, &(&1 != nil))
              else
                response
              end

            if filtered_response != nil and filtered_response != [] do
              conn
              |> put_resp_content_type("application/json")
              |> send_resp(200, Jason.encode!(filtered_response))
            else
              # For notifications, return 202 Accepted with no body
              conn
              |> send_resp(202, "")
            end
          else
            error_response = %{
              jsonrpc: "2.0",
              error: %{
                code: -32000,
                message: "Session ID required for non-initialization requests"
              },
              id: get_request_id(json_data)
            }

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(400, Jason.encode!(error_response))
          end
        end
    end
  end

  def sse(conn, _params) do
    # Check if client is requesting SSE stream
    accept_header = get_req_header(conn, "accept") |> List.first() || ""

    if String.contains?(accept_header, "text/event-stream") do
      session_id =
        get_req_header(conn, @session_id_header) |> List.first() || generate_session_id()

      # Start SSE stream
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> put_resp_header("access-control-allow-origin", "*")
      |> put_resp_header("access-control-allow-headers", "content-type, #{@session_id_header}")
      |> put_resp_header(@session_id_header, session_id)
      |> send_chunked(200)
      |> handle_sse_stream(session_id)
    else
      # Return 405 Method Not Allowed if not requesting SSE
      conn
      |> put_resp_header("allow", "POST")
      |> send_resp(405, "Method Not Allowed")
    end
  end

  defp handle_sse_stream(conn, session_id) do
    # Send endpoint message first - this tells the proxy where to send JSON-RPC messages
    endpoint_event = "event: endpoint\ndata: http://localhost:4000/mcp\n\n"
    {:ok, conn} = chunk(conn, endpoint_event)

    # Keep connection alive with periodic pings
    keep_alive_loop(conn, session_id)
  end

  defp keep_alive_loop(conn, session_id) do
    receive do
      {:mcp_message, message} ->
        event_data = "data: #{Jason.encode!(message)}\n\n"

        case chunk(conn, event_data) do
          {:ok, conn} -> keep_alive_loop(conn, session_id)
          {:error, _} -> conn
        end
    after
      # 30 second ping
      30_000 ->
        ping_event = ": keepalive\n\n"

        case chunk(conn, ping_event) do
          {:ok, conn} -> keep_alive_loop(conn, session_id)
          {:error, _} -> conn
        end
    end
  end

  defp is_initialize_request?(data) when is_map(data) do
    data["method"] == "initialize"
  end

  defp is_initialize_request?(data) when is_list(data) do
    Enum.any?(data, &is_initialize_request?/1)
  end

  defp is_initialize_request?(_), do: false

  defp get_request_id(data) when is_map(data), do: data["id"]

  defp get_request_id(data) when is_list(data) do
    case Enum.find(data, &Map.has_key?(&1, "id")) do
      %{"id" => id} -> id
      _ -> nil
    end
  end

  defp get_request_id(_), do: nil

  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
