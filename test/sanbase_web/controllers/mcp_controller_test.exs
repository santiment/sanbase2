defmodule SanbaseWeb.MCPControllerTest do
  use SanbaseWeb.ConnCase, async: true

  @initialize_request %{
    "jsonrpc" => "2.0",
    "id" => "1",
    "method" => "initialize",
    "params" => %{
      "protocolVersion" => "2025-03-26",
      "capabilities" => %{},
      "clientInfo" => %{
        "name" => "test-client",
        "version" => "1.0.0"
      }
    }
  }

  @tools_list_request %{
    "jsonrpc" => "2.0",
    "id" => "2",
    "method" => "tools/list"
  }

  @say_hi_request %{
    "jsonrpc" => "2.0",
    "id" => "3",
    "method" => "tools/call",
    "params" => %{
      "name" => "say_hi",
      "arguments" => %{
        "name" => "Test User",
        "language" => "en"
      }
    }
  }

  defp post_json(conn, path, data) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(data))
  end

  defp post_raw_json(conn, path, json_string) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, json_string)
  end

  describe "POST /mcp" do
    test "handles initialize request", %{conn: conn} do
      conn = post_json(conn, "/mcp", @initialize_request)

      assert %{
               "jsonrpc" => "2.0",
               "id" => "1",
               "result" => %{
                 "protocolVersion" => "2025-03-26",
                 "capabilities" => %{"tools" => %{"listChanged" => true}},
                 "serverInfo" => %{
                   "name" => "Sanbase MCP Server",
                   "version" => "1.0.0",
                   "protocolVersion" => "2025-03-26"
                 }
               }
             } = json_response(conn, 200)
    end

    test "handles tools/list request", %{conn: conn} do
      conn = post_json(conn, "/mcp", @tools_list_request)

      assert %{
               "jsonrpc" => "2.0",
               "id" => "2",
               "result" => %{
                 "tools" => [
                   %{
                     "name" => "say_hi",
                     "description" => "A friendly greeting tool that says hello"
                   }
                 ]
               }
             } = json_response(conn, 200)
    end

    test "handles tools/call request", %{conn: conn} do
      conn = post_json(conn, "/mcp", @say_hi_request)

      assert %{
               "jsonrpc" => "2.0",
               "id" => "3",
               "result" => %{
                 "content" => [
                   %{
                     "type" => "text",
                     "text" => "Hello, Test User! 👋"
                   }
                 ],
                 "isError" => false
               }
             } = json_response(conn, 200)
    end

    test "handles notification (initialized)", %{conn: conn} do
      notification = %{
        "jsonrpc" => "2.0",
        "method" => "initialized"
      }

      conn = post_json(conn, "/mcp", notification)

      # Notifications don't return responses (empty object)
      assert %{} = json_response(conn, 200)
    end

    test "handles batch request", %{conn: conn} do
      batch_request = [@initialize_request, @tools_list_request]

      conn = post_json(conn, "/mcp", batch_request)

      response = json_response(conn, 200)
      assert is_list(response)
      assert length(response) == 2

      # Verify both responses are present
      assert Enum.any?(response, fn r -> r["id"] == "1" and r["result"]["protocolVersion"] end)
      assert Enum.any?(response, fn r -> r["id"] == "2" and r["result"]["tools"] end)
    end

    test "handles invalid JSON", %{conn: conn} do
      conn = post_raw_json(conn, "/mcp", "invalid json")

      assert %{
               "jsonrpc" => "2.0",
               "error" => %{
                 "code" => -32700,
                 "message" => "Parse error"
               }
             } = json_response(conn, 400)
    end

    test "handles invalid JSON-RPC request", %{conn: conn} do
      invalid_request = %{"invalid" => "request"}

      conn = post_json(conn, "/mcp", invalid_request)

      assert %{
               "jsonrpc" => "2.0",
               "error" => %{
                 "code" => -32600,
                 "message" => "Invalid Request"
               }
             } = json_response(conn, 200)
    end

    test "handles unknown method", %{conn: conn} do
      unknown_request = %{
        "jsonrpc" => "2.0",
        "id" => "999",
        "method" => "unknown/method"
      }

      conn = post_json(conn, "/mcp", unknown_request)

      assert %{
               "jsonrpc" => "2.0",
               "id" => "999",
               "error" => %{
                 "code" => -32601,
                 "message" => "Method not found",
                 "data" => %{"method" => "unknown/method"}
               }
             } = json_response(conn, 200)
    end
  end
end
