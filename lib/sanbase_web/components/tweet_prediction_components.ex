defmodule SanbaseWeb.TweetPredictionComponents do
  use Phoenix.Component

  @doc """
  Renders a tweet card with prediction buttons
  """
  attr :tweet, :map, required: true
  attr :interesting_case, :boolean, default: false
  attr :rest, :global

  def tweet_card(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 p-3" id={"tweet-#{@tweet["id"]}"} {@rest}>
      <div class="flex justify-between text-xs text-base-content/60 mb-1">
        <span class="font-bold text-primary">@{@tweet["screen_name"]}</span>
        <span>{format_date(@tweet["timestamp"])}</span>
      </div>
      <p class="mb-2 text-sm whitespace-pre-line">{@tweet["text"]}</p>
      <div class="flex items-center gap-2 mt-2 flex-wrap">
        <label class="label cursor-pointer gap-2 py-0">
          <input
            type="checkbox"
            class="checkbox checkbox-xs checkbox-primary"
            checked={@interesting_case}
            phx-click="toggle_interesting"
            phx-value-id={@tweet["id"]}
          />
          <span class="text-xs">Interesting Case</span>
        </label>

        <button
          class="btn btn-xs btn-success"
          phx-click="submit_classification"
          phx-value-id={@tweet["id"]}
          phx-value-prediction="prediction"
        >
          Submit as Prediction
        </button>

        <button
          class="btn btn-xs btn-error"
          phx-click="submit_classification"
          phx-value-id={@tweet["id"]}
          phx-value-prediction="not_prediction"
        >
          Submit as Not
        </button>

        <a
          href={@tweet["url"]}
          target="_blank"
          rel="noopener noreferrer"
          class="link link-primary text-xs"
        >
          View on X
        </a>
      </div>
    </div>
    """
  end

  @doc """
  Renders a header with title and refresh button
  """
  attr :title, :string, default: "Tweet Predictions Classifier"
  attr :loading, :boolean, default: false

  def tweet_header(assigns) do
    ~H"""
    <div class="flex justify-between items-center mb-3">
      <h2 class="text-xl font-bold">{@title}</h2>
      <button class="btn btn-sm btn-primary" phx-click="refresh" disabled={@loading}>
        Refresh
      </button>
    </div>
    """
  end

  @doc """
  Renders a loading indicator
  """
  def loading_indicator(assigns) do
    ~H"""
    <div class="flex justify-center items-center h-16 gap-2">
      <span class="loading loading-spinner loading-sm"></span>
      <p class="text-sm text-base-content/60">Loading tweets...</p>
    </div>
    """
  end

  @doc """
  Renders an empty state when no unclassified tweets are available
  """
  def empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center h-32 text-center gap-2">
      <p class="text-sm text-base-content/60">No unclassified tweets available</p>
      <button class="btn btn-xs btn-primary" phx-click="refresh">
        Check for new tweets
      </button>
    </div>
    """
  end

  # Helper functions
  defp format_date(datetime_str) do
    case DateTime.from_iso8601(datetime_str) do
      {:ok, datetime, _offset} ->
        datetime
        |> DateTime.to_naive()
        |> NaiveDateTime.to_string()
        |> String.replace("T", ", ")

      _ ->
        datetime_str
    end
  end
end
