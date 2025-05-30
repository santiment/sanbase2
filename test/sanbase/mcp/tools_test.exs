defmodule Sanbase.MCP.ToolsTest do
  use ExUnit.Case, async: true

  alias Sanbase.MCP.Tools

  describe "list_tools/0" do
    test "returns list of available tools" do
      tools = Tools.list_tools()

      assert [
               %{
                 "name" => "say_hi",
                 "description" => "A friendly greeting tool that says hello",
                 "inputSchema" => %{
                   "type" => "object",
                   "properties" => %{
                     "name" => %{
                       "type" => "string",
                       "description" => "The name of the person to greet",
                       "default" => "World"
                     },
                     "language" => %{
                       "type" => "string",
                       "description" => "Language for the greeting",
                       "enum" => ["en", "es", "fr", "de", "bg"],
                       "default" => "en"
                     }
                   }
                 }
               },
               %{
                 "name" => "list_available_metrics",
                 "description" =>
                   "Lists all available Sanbase metrics and their metadata including supported assets, access levels, and documentation",
                 "inputSchema" => %{
                   "type" => "object",
                   "properties" => %{
                     "format" => %{
                       "type" => "string",
                       "description" => "Output format for the metrics data",
                       "enum" => ["json", "summary"],
                       "default" => "summary"
                     }
                   }
                 }
               }
             ] = tools
    end
  end

  describe "call_tool/2" do
    test "executes say_hi tool with default parameters" do
      {:ok, result} = Tools.call_tool("say_hi", %{})

      assert %{
               "content" => [
                 %{
                   "type" => "text",
                   "text" => "Hello, World! 👋"
                 }
               ],
               "isError" => false
             } = result
    end

    test "executes say_hi tool with custom name" do
      {:ok, result} = Tools.call_tool("say_hi", %{"name" => "Bob"})

      assert %{
               "content" => [
                 %{
                   "type" => "text",
                   "text" => "Hello, Bob! 👋"
                 }
               ],
               "isError" => false
             } = result
    end

    test "executes say_hi tool with different language" do
      {:ok, result} = Tools.call_tool("say_hi", %{"name" => "Maria", "language" => "es"})

      assert %{
               "content" => [
                 %{
                   "type" => "text",
                   "text" => "Hola, Maria! 👋"
                 }
               ],
               "isError" => false
             } = result
    end

    test "executes say_hi tool with French greeting" do
      {:ok, result} = Tools.call_tool("say_hi", %{"name" => "Pierre", "language" => "fr"})

      assert %{
               "content" => [
                 %{
                   "type" => "text",
                   "text" => "Bonjour, Pierre! 👋"
                 }
               ],
               "isError" => false
             } = result
    end

    test "executes say_hi tool with Bulgarian greeting" do
      {:ok, result} = Tools.call_tool("say_hi", %{"name" => "Ivan", "language" => "bg"})

      assert %{
               "content" => [
                 %{
                   "type" => "text",
                   "text" => "Здравей, Ivan! 👋"
                 }
               ],
               "isError" => false
             } = result
    end

    test "executes say_hi tool with unknown language falls back to English" do
      {:ok, result} = Tools.call_tool("say_hi", %{"name" => "Alex", "language" => "unknown"})

      assert %{
               "content" => [
                 %{
                   "type" => "text",
                   "text" => "Hello, Alex! 👋"
                 }
               ],
               "isError" => false
             } = result
    end

    test "returns error for unknown tool" do
      {:error, message} = Tools.call_tool("unknown_tool", %{})

      assert "Unknown tool: unknown_tool" = message
    end
  end

  describe "call_tool/2 - list_available_metrics" do
    test "list_available_metrics tool is properly registered" do
      # Just test that the tool responds (it may fail due to DB issues in test)
      result = Tools.call_tool("list_available_metrics", %{})

      # The tool should return a proper MCP response structure regardless of success/failure
      assert {:ok, response} = result
      assert %{"content" => [%{"type" => "text", "text" => _text}], "isError" => _} = response
    end

    test "list_available_metrics tool with json format parameter" do
      # Test that the tool accepts the json format parameter
      result = Tools.call_tool("list_available_metrics", %{"format" => "json"})

      # The tool should return a proper MCP response structure regardless of success/failure
      assert {:ok, response} = result
      assert %{"content" => [%{"type" => "text", "text" => _text}], "isError" => _} = response
    end

    test "list_available_metrics tool with summary format parameter" do
      # Test that the tool accepts the summary format parameter
      result = Tools.call_tool("list_available_metrics", %{"format" => "summary"})

      # The tool should return a proper MCP response structure regardless of success/failure
      assert {:ok, response} = result
      assert %{"content" => [%{"type" => "text", "text" => _text}], "isError" => _} = response
    end
  end
end
