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
end
