defmodule Sanbase.MCP.InsightDiscoveryTool do
  @moduledoc "Discovery tool for santiment crypto insights with basic info (id, title, tags, link) in time period"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response
  alias Sanbase.Insight.Post

  schema do
    field(:time_period, :string,
      required: false,
      description: """
      Time period for insights (e.g., '7d', '30d', '90d').
      This parameter defines the range of insights to fetch - from <time_period> time
      ago up until now.

      Defaults to 30d.
      """
    )
  end

  @impl true
  def execute(params, frame) do
    do_execute(params, frame)
  end

  defp do_execute(params, frame) do
    time_period = params[:time_period] || "30d"

    with {:ok, {from_datetime, to_datetime}} <- parse_time_period(time_period),
         {:ok, insights} <- fetch_insights(from_datetime, to_datetime) do
      response_data = %{
        insights: insights,
        time_period: time_period,
        total_count: length(insights),
        period_start: DateTime.to_iso8601(from_datetime),
        period_end: DateTime.to_iso8601(to_datetime)
      }

      {:reply, Response.json(Response.tool(), response_data), frame}
    else
      {:error, reason} ->
        {:reply, Response.error(Response.tool(), reason), frame}
    end
  end

  defp parse_time_period(time_period) do
    if Sanbase.DateTimeUtils.valid_interval?(time_period) do
      seconds = Sanbase.DateTimeUtils.str_to_sec(time_period)
      to_datetime = DateTime.utc_now()
      from_datetime = DateTime.add(to_datetime, -seconds, :second)
      {:ok, {from_datetime, to_datetime}}
    else
      {:error, "Invalid time period format. Use format like '30d', '7d', '2w', '24h'"}
    end
  end

  defp fetch_insights(from_datetime, to_datetime) do
    # NOTE: This fetches both public and paywalled insights.
    # Leaving a note so we can decide later if we want to check the user's
    # subscription when fetching insights, so we don't leak paywalled insights
    # via the MCP
    insights =
      Post.public_insights(
        from: from_datetime,
        to: to_datetime,
        page: 1,
        page_size: 100,
        preload: [:tags, :user]
      )
      |> Enum.map(&format_insight_summary/1)

    {:ok, insights}
  rescue
    error ->
      {:error, "Failed to fetch insights: #{inspect(error)}"}
  end

  defp format_insight_summary(post) do
    %{
      id: post.id,
      title: post.title,
      tags: Enum.map(post.tags, & &1.name),
      link: SanbaseWeb.Endpoint.insight_url(post.id),
      published_at: Sanbase.DateTimeUtils.to_iso8601(post.published_at),
      author: post.user.username || "Anonymous",
      prediction: post.prediction
    }
  end
end
