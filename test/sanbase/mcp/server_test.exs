defmodule Sanbase.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias Sanbase.MCP.Server

  describe "get_capabilities/0" do
    test "returns expected capabilities" do
      capabilities = Server.get_capabilities()

      assert %{
               "tools" => %{
                 "listChanged" => true
               }
             } = capabilities
    end
  end

  describe "get_server_info/0" do
    test "returns server information" do
      server_info = Server.get_server_info()

      assert %{
               "name" => "Sanbase MCP Server",
               "version" => "1.0.0",
               "protocolVersion" => "2025-03-26"
             } = server_info
    end
  end

  describe "handle_request/1" do
    test "handles initialize request" do
      request = %{
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

      {:ok, response} = Server.handle_request(request)

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
             } = response
    end

    test "handles tools/list request" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => "2",
        "method" => "tools/list"
      }

      {:ok, response} = Server.handle_request(request)

      assert %{
               "jsonrpc" => "2.0",
               "id" => "2",
               "result" => %{
                 "tools" => tools
               }
             } = response

      assert [
               %{"name" => "say_hi"},
               %{"name" => "list_available_metrics"}
             ] = tools
    end

    test "handles tools/call request for say_hi" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => "3",
        "method" => "tools/call",
        "params" => %{
          "name" => "say_hi",
          "arguments" => %{
            "name" => "Alice",
            "language" => "en"
          }
        }
      }

      {:ok, response} = Server.handle_request(request)

      assert %{
               "jsonrpc" => "2.0",
               "id" => "3",
               "result" => %{
                 "content" => [
                   %{
                     "type" => "text",
                     "text" => "Hello, Alice! 👋"
                   }
                 ],
                 "isError" => false
               }
             } = response
    end

    test "handles unknown method" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => "4",
        "method" => "unknown/method"
      }

      {:error, response} = Server.handle_request(request)

      assert %{
               "code" => -32601,
               "message" => "Method not found"
             } = response
    end

    test "handles invalid request" do
      invalid_request = %{"invalid" => "request"}

      {:error, response} = Server.handle_request(invalid_request)

      assert %{
               "code" => -32600,
               "message" => "Invalid Request"
             } = response
    end
  end
end
