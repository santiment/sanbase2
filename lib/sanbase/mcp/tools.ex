defmodule Sanbase.MCP.Tools do
  @moduledoc """
  Defines and implements tools available through the MCP server.

  This module manages the tools that MCP clients can discover and call.
  Each tool has a schema definition and an implementation.
  """

  require Logger

  @doc """
  Lists all available tools with their schemas.
  """
  @spec list_tools() :: list(map())
  def list_tools do
    [
      say_hi_tool_schema()
    ]
  end

  @doc """
  Calls a specific tool with the given arguments.
  """
  @spec call_tool(String.t(), map()) :: {:ok, map()} | {:error, String.t()}
  def call_tool("say_hi", arguments) do
    execute_say_hi(arguments)
  end

  def call_tool(unknown_tool, _arguments) do
    Logger.warning("Unknown tool called: #{unknown_tool}")
    {:error, "Unknown tool: #{unknown_tool}"}
  end

  # Tool schemas

  defp say_hi_tool_schema do
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
  end

  # Tool implementations

  defp execute_say_hi(arguments) do
    name = Map.get(arguments, "name", "World")
    language = Map.get(arguments, "language", "en")

    greeting =
      case language do
        "en" -> "Hello"
        "es" -> "Hola"
        "fr" -> "Bonjour"
        "de" -> "Hallo"
        "bg" -> "Здравей"
        _ -> "Hello"
      end

    message = "#{greeting}, #{name}! 👋"

    Logger.info("MCP say_hi tool called with name=#{name}, language=#{language}")

    result = %{
      "content" => [
        %{
          "type" => "text",
          "text" => message
        }
      ],
      "isError" => false
    }

    {:ok, result}
  end
end
