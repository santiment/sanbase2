defmodule SanbaseWeb.McpServers.TrendingWordsServer do
  @moduledoc """
  MCP server for accessing trending words and projects data.

  This server provides tools to fetch currently trending words
  from crypto social media channels, helping discover emerging topics and
  developing stories in the crypto community.
  """
  use Toolmux.Server

  alias Sanbase.SocialData.TrendingWords

  @impl true
  def server_info() do
    %{
      name: "Trending Words Server",
      version: "1.0.0",
      description: "Access trending words from crypto social media",
      capabilities: %{
        tools: %{}
      }
    }
  end

  @impl true
  def list_tools() do
    [
      %{
        name: "get_trending_words",
        description: "Get currently trending words from crypto social media",
        inputSchema: %{
          type: "object",
          properties: %{
            size: %{
              type: "integer",
              description: "Number of trending words to return",
              minimum: 1,
              maximum: 100,
              default: 10
            },
            source: %{
              type: "string",
              description: "Data source (all, reddit, telegram, twitter_crypto, 4chan)",
              enum: ["all", "reddit", "telegram", "twitter_crypto", "4chan"],
              default: "all"
            }
          }
        }
      }
    ]
  end

  @impl true
  def call_tool("get_trending_words", params) do
    size = Map.get(params, "size", 10)
    source = Map.get(params, "source", "all") |> String.to_atom()

    case TrendingWords.get_currently_trending_words(size, source) do
      {:ok, words} ->
        {:ok,
         %{
           words: words,
           count: length(words),
           source: source,
           timestamp: DateTime.utc_now()
         }}

      {:error, error} ->
        {:error, "Failed to fetch trending words: #{error}"}
    end
  end

  def call_tool(name, _params) do
    {:error, "Unknown tool: #{name}"}
  end
end
