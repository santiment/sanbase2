defmodule Sanbase.MCP.TrendingStoriesTool do
  @moduledoc """
  Fetch current trending crypto stories with sentiment analysis

  ## Parameters

  - `time_period` - Time period for trending stories (e.g., '1h', '6h', '1d', '7d'). Defaults to '1h' (last hour).
  - `size` - Number of trending stories to return (max 30). Defaults to 10.

  ## Response

  - `trending_stories` - List of trending stories.
  - `time_period` - Time period for trending stories.
  - `size` - Number of trending stories to return.
  - `period_start` - Start time of the time period.
  - `period_end` - End time of the time period.
  - `total_time_periods` - Total number of time periods.

  ## Trending stories

  - `title` - Title of the story.
  - `summary` - Summary of the story.
  - `bearish_sentiment_ratio` - Bearish sentiment ratio.
  - `bullish_sentiment_ratio` - Bullish sentiment ratio.
  - `score` - Score of the story.
  - `query` - Query used to find the story.
  - `related_tokens` - List of related tokens. They have the format `BTC_bitcoin` - first part is the ticker,
  second part is the slug in Sanbase.
  """

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field(:time_period, :string,
      required: false,
      description: """
      Time period for trending stories (e.g., '1h', '6h', '1d', '7d').
      This parameter defines how far back to look for trending stories.

      Defaults to '1h' (last hour).
      """
    )

    field(:size, :integer,
      required: false,
      description: """
      Number of trending stories to return (max 30).

      Defaults to 10.
      """
    )
  end

  @impl true
  def execute(params, frame) do
    do_execute(params, frame)
  end

  defp do_execute(params, frame) do
    time_period = params[:time_period] || "1h"
    size = params[:size] || 10

    with {:ok, {from_datetime, to_datetime}} <- parse_time_period(time_period),
         {:ok, validated_size} <- validate_size(size),
         {:ok, stories_data} <- fetch_trending_stories(from_datetime, to_datetime, validated_size) do
      response_data = %{
        trending_stories: stories_data,
        time_period: time_period,
        size: validated_size,
        period_start: DateTime.to_iso8601(from_datetime),
        period_end: DateTime.to_iso8601(to_datetime),
        total_time_periods: length(stories_data)
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
      {:error, "Invalid time period format. Use format like '1h', '6h', '1d', '7d'"}
    end
  end

  defp validate_size(size) when is_integer(size) and size > 0 and size <= 30 do
    {:ok, size}
  end

  defp validate_size(size) when is_integer(size) do
    {:error, "Size must be between 1 and 30, got: #{size}"}
  end

  defp validate_size(_) do
    {:error, "Size must be an integer"}
  end

  defp fetch_trending_stories(from_datetime, to_datetime, size) do
    # Use the interval based on the time period
    interval = determine_interval(from_datetime, to_datetime)

    case Sanbase.SocialData.TrendingStories.get_trending_stories(
           from_datetime,
           to_datetime,
           interval,
           size
         ) do
      {:ok, stories_map} ->
        formatted_stories =
          stories_map
          |> Enum.sort_by(fn {datetime, _} -> datetime end, {:asc, DateTime})
          |> Enum.map(fn {datetime, top_stories} ->
            %{
              datetime: DateTime.to_iso8601(datetime),
              top_stories:
                top_stories
                |> Enum.map(&format_story/1)
            }
          end)

        {:ok, formatted_stories}

      {:error, reason} ->
        {:error, "Failed to fetch trending stories: #{inspect(reason)}"}
    end
  rescue
    error ->
      {:error, "Failed to fetch trending stories: #{inspect(error)}"}
  end

  defp determine_interval(from_datetime, to_datetime) do
    diff_hours = DateTime.diff(to_datetime, from_datetime, :hour)

    cond do
      diff_hours <= 24 -> "1h"
      # 1 week
      diff_hours <= 168 -> "6h"
      true -> "1d"
    end
  end

  defp format_story(story) do
    %{
      title: story.title,
      summary: story.summary,
      bearish_sentiment_ratio: story.bearish_ratio,
      bullish_sentiment_ratio: story.bullish_ratio,
      score: story.score,
      query: story.search_text,
      related_tokens: story.related_tokens || []
    }
  end
end
