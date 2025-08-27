defmodule Sanbase.MCP.FetchInsightsTool do
  @moduledoc "Fetch full text content for specific santiment crypto insights IDs"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Sanbase.Insight.Post

  schema do
    field(:insight_ids, :any,
      required: true,
      description: "Array of santiment crypto insights IDs to fetch full content for"
    )
  end

  @impl true
  def execute(params, frame) do
    do_execute(params, frame)
  end

  defp do_execute(%{insight_ids: insight_ids}, frame) do
    with {:ok, parsed_ids} <- parse_insight_ids(insight_ids),
         {:ok, insights} <- fetch_insight_details(parsed_ids) do
      response_data = %{
        insights: insights,
        total_count: length(insights),
        requested_ids: parsed_ids
      }

      {:reply, Response.json(Response.tool(), response_data), frame}
    else
      {:error, reason} ->
        {:reply, Response.error(Response.tool(), reason), frame}
    end
  end

  defp parse_insight_ids(insight_ids) when is_list(insight_ids) do
    parsed = Enum.map(insight_ids, &ensure_integer/1)
    {:ok, parsed}
  rescue
    _ -> {:error, "Invalid insight IDs format. Expected array of integers."}
  end

  defp parse_insight_ids(insight_ids) when is_binary(insight_ids) do
    # Handle case where it comes as a string like "[8857, 8856, 8855]"
    case Jason.decode(insight_ids) do
      {:ok, list} when is_list(list) ->
        parse_insight_ids(list)

      _ ->
        {:error,
         "Invalid insight IDs format. Expected array of integers or valid JSON array string."}
    end
  end

  defp parse_insight_ids(_),
    do: {:error, "Invalid insight IDs format. Expected array of integers."}

  defp ensure_integer(value) when is_integer(value), do: value
  defp ensure_integer(value) when is_binary(value), do: String.to_integer(value)

  defp ensure_integer(value),
    do: raise(ArgumentError, "Cannot convert #{inspect(value)} to integer")

  defp fetch_insight_details(insight_ids) do
    {:ok, posts} = Post.by_ids(insight_ids, preload: [:tags, :user, :metrics])

    insights = Enum.map(posts, &format_insight_detail/1)
    {:ok, insights}
  rescue
    error ->
      {:error, "Failed to fetch insight details: #{inspect(error)}"}
  end

  defp format_insight_detail(post) do
    %{
      id: post.id,
      title: post.title,
      short_desc: post.short_desc,
      text: post.text,
      published_at: Sanbase.DateTimeUtils.to_iso8601(post.published_at),
      author: %{
        username: post.user.username || "Unnamed"
      },
      tags: Enum.map(post.tags, & &1.name),
      metrics: Enum.map(post.metrics, & &1.name),
      prediction: post.prediction,
      link: SanbaseWeb.Endpoint.insight_url(post.id)
    }
  end
end
