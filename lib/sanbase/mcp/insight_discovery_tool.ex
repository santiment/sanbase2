defmodule Sanbase.MCP.InsightDiscoveryTool do
  @moduledoc """
  List Santiment insights (analyst-written crypto articles) published in a
  lookback window. Returns metadata only — id, title, tags, author, link,
  published_at, prediction — never the article body.

  ## When to use

  - The user asks what Santiment analysts have written or published recently.
  - As step 1 of a two-step read: discover ids here, then pass them to
    `fetch_insights_tool` for the full text.

  ## When not to use

  - Full text of an insight — use `fetch_insights_tool` (it needs ids, so call
    this tool first).
  - What the market is talking about right now — use `trending_stories_tool`
    (stories only) or `combined_trends_tool` (stories + trending words).
    Insights are human-authored articles, not live social signal.
  - Numeric metric timeseries for an asset — use `fetch_metric_data_tool`.
  - Ranking or screening assets by a metric — use `assets_by_metric_tool`.

  ## Parameters

  - `time_period` (optional, default `"30d"`) — lookback window as
    `<integer><unit>`, unit one of `s`, `m`, `h`, `d`, `w`, `y`
    (e.g. `"12h"`, `"7d"`, `"90d"`, `"1y"`). The window is always
    `now - time_period` .. `now`; absolute dates and future ranges are not
    supported. An unparsable value returns an error, not a default.

  There is no tag, author, asset or full-text filter — filter the returned
  list yourself.

  ## Behavior

  - Read-only: no writes, no state change, nothing destructive.
  - Requires an authenticated Santiment account (API key or OAuth token);
    every call counts against the account plan's MCP rate limits.
  - Returns only published, moderator-approved insights, newest first, hard
    capped at 100 per call. A wide `time_period` can hit that cap and silently
    omit the oldest insights — if `total_count` is 100, narrow the window and
    call again.

  ## Response

  JSON object:

      {
        "insights": [
          {
            "id": 1234,                          // integer, feed to fetch_insights_tool
            "title": "...",
            "tags": ["BTC", "bitcoin"],          // asset tickers/slugs and topics
            "link": "https://app.santiment.net/insights/read/1234",
            "published_at": "2025-01-30T10:00:00Z",
            "author": "username",                // "Anonymous" when unset
            "prediction": "semi_bullish"         // heavy_bullish | semi_bullish |
                                                 // semi_bearish | heavy_bearish |
                                                 // none | unspecified | null
          }
        ],
        "time_period": "30d",
        "total_count": 1,
        "period_start": "2024-12-31T10:00:00Z",
        "period_end": "2025-01-30T10:00:00Z"
      }

  An empty `insights` list with `total_count: 0` means nothing was published in
  the window — a valid result, not an error.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Sanbase.Insight.Post
  alias Sanbase.MCP.Utils

  @impl true
  def annotations do
    %{
      "title" => "Discover Insights",
      "readOnlyHint" => true,
      "destructiveHint" => false,
      "openWorldHint" => false
    }
  end

  schema do
    field(:time_period, :string,
      required: false,
      description: """
      Lookback window as <integer><unit>, unit one of s, m, h, d, w, y
      (e.g. '12h', '7d', '30d', '90d', '1y'). Insights published in
      `now - time_period` .. `now` are returned. Absolute dates and future
      ranges are not supported. Defaults to '30d'.
      """
    )
  end

  @impl true
  def execute(params, frame) do
    do_execute(params, frame)
  end

  defp do_execute(params, frame) do
    time_period = params[:time_period] || "30d"

    with {:ok, {from_datetime, to_datetime}} <- Utils.parse_time_period(time_period),
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
      published_at: Sanbase.Utils.DateTime.to_iso8601(post.published_at),
      author: post.user.username || "Anonymous",
      prediction: post.prediction
    }
  end
end
