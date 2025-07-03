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
      say_hi_tool_schema(),
      list_available_metrics_tool_schema()
    ]
  end

  @doc """
  Calls a specific tool with the given arguments.
  """
  @spec call_tool(String.t(), map()) :: {:ok, map()} | {:error, String.t()}
  def call_tool("say_hi", arguments) do
    execute_say_hi(arguments)
  end

  def call_tool("list_available_metrics", arguments) do
    execute_list_available_metrics(arguments)
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

  defp list_available_metrics_tool_schema do
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

  defp execute_list_available_metrics(arguments) do
    format = Map.get(arguments, "format", "summary")

    Logger.info("MCP list_available_metrics tool called with format=#{format}")

    try do
      metrics_map = Sanbase.AvailableMetrics.get_metrics_map()

      content_text =
        case format do
          "json" ->
            metrics_map
            |> Jason.encode!(pretty: true)

          "summary" ->
            generate_metrics_summary(metrics_map)
        end

      result = %{
        "content" => [
          %{
            "type" => "text",
            "text" => content_text
          }
        ],
        "isError" => false
      }

      {:ok, result}
    rescue
      error ->
        Logger.error("Error in list_available_metrics: #{inspect(error)}")

        result = %{
          "content" => [
            %{
              "type" => "text",
              "text" => "Error retrieving metrics: #{Exception.message(error)}"
            }
          ],
          "isError" => true
        }

        {:ok, result}
    end
  end

  defp generate_metrics_summary(metrics_map) do
    total_metrics = map_size(metrics_map)

    status_counts =
      metrics_map
      |> Enum.group_by(fn {_metric, data} -> data.status end)
      |> Enum.map(fn {status, metrics} -> "#{status}: #{length(metrics)}" end)
      |> Enum.join(", ")

    access_levels =
      metrics_map
      |> Enum.group_by(fn {_metric, data} -> Map.get(data.access || %{}, "sanapi", "unknown") end)
      |> Enum.map(fn {access, metrics} -> "#{access}: #{length(metrics)}" end)
      |> Enum.join(", ")

    sample_metrics =
      metrics_map
      |> Enum.take(5)
      |> Enum.map(fn {metric, data} ->
        "• #{metric} (#{data.status}) - #{length(data.available_assets)} assets, #{data.frequency}"
      end)
      |> Enum.join("\n")

    """
    📊 Sanbase Available Metrics Summary

    Total Metrics: #{total_metrics}

    Status Distribution: #{status_counts}

    Access Levels: #{access_levels}

    Sample Metrics:
    #{sample_metrics}

    Use format="json" for complete detailed data including all metrics, supported assets, selectors, and documentation.
    """
  end
end
