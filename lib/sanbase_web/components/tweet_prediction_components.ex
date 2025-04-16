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
    <div class="border rounded-lg p-3" id={"tweet-#{@tweet["id"]}"} {@rest}>
      <div class="flex justify-between text-xs text-gray-500 mb-1">
        <span class="font-bold">@{@tweet["screen_name"]}</span>
        <span>{format_date(@tweet["timestamp"])}</span>
      </div>
      <p class="mb-2 text-sm whitespace-pre-line">{@tweet["text"]}</p>
      <div class="flex items-center gap-2 mt-2">
        <div class="flex items-center gap-2">
          <label class="inline-flex items-center text-xs">
            <input
              type="checkbox"
              class="form-checkbox h-3 w-3 text-blue-600"
              checked={@interesting_case}
              phx-click="toggle_interesting"
              phx-value-id={@tweet["id"]}
            />
            <span class="ml-1 text-gray-700">Interesting Case</span>
          </label>

          <button
            class="text-xs py-1 px-2 rounded bg-blue-500 text-white hover:bg-blue-600"
            phx-click="submit_classification"
            phx-value-id={@tweet["id"]}
            phx-value-prediction="prediction"
          >
            Submit as Prediction
          </button>

          <button
            class="text-xs py-1 px-2 rounded bg-blue-500 text-white hover:bg-blue-600"
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
            class="text-xs text-blue-500 hover:underline"
          >
            View on X
          </a>
        </div>
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
      <button
        class="bg-blue-500 hover:bg-blue-700 text-white text-sm font-bold py-1 px-3 rounded"
        phx-click="refresh"
        disabled={@loading}
      >
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
    <div class="flex justify-center items-center h-16">
      <p class="text-sm text-gray-500">Loading tweets...</p>
    </div>
    """
  end

  @doc """
  Renders an empty state when no unclassified tweets are available
  """
  def empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center h-32 text-center">
      <p class="text-sm text-gray-500 mb-2">No unclassified tweets available</p>
      <button
        class="bg-blue-500 hover:bg-blue-700 text-white text-xs font-bold py-1 px-2 rounded"
        phx-click="refresh"
      >
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
