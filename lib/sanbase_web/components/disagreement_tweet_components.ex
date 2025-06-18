defmodule SanbaseWeb.DisagreementTweetComponents do
  use Phoenix.Component

  @doc """
  Renders a disagreement tweet card with AI classification details and voting buttons
  """
  attr :tweet, :map, required: true
  attr :show_classification_buttons, :boolean, default: false
  attr :user_id, :integer, required: true
  attr :rest, :global

  def disagreement_tweet_card(assigns) do
    ~H"""
    <div
      class="border rounded-lg p-4 bg-white shadow-sm"
      id={"disagreement-tweet-#{@tweet.tweet_id}"}
      {@rest}
    >
      <div class="flex justify-between items-start mb-3">
        <div class="flex items-center gap-3">
          <span class="font-bold text-blue-600 text-sm">@{@tweet.screen_name}</span>
          <span class="text-xs text-gray-500">{format_date(@tweet.timestamp)}</span>
          <span class="text-xs bg-purple-100 text-purple-800 px-2 py-1 rounded-full font-medium">
            {@tweet.classification_count} {if @tweet.classification_count == 1,
              do: "person",
              else: "people"} classified
          </span>
          <span
            :if={@tweet.classification_count >= 5}
            class={[
              "text-xs px-2 py-1 rounded-full font-medium",
              if(@tweet.experts_is_prediction,
                do: "bg-green-100 text-green-800",
                else: "bg-red-100 text-red-800"
              )
            ]}
          >
            {if @tweet.experts_is_prediction, do: "✅ PREDICTION", else: "❌ NOT PREDICTION"}
          </span>
        </div>

        <a
          href={@tweet.url}
          target="_blank"
          rel="noopener noreferrer"
          class="text-xs text-blue-500 hover:underline flex items-center gap-1"
        >
          <span>View on X</span>
          <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
            <path
              fill-rule="evenodd"
              d="M10.293 3.293a1 1 0 011.414 0l6 6a1 1 0 010 1.414l-6 6a1 1 0 01-1.414-1.414L14.586 11H3a1 1 0 110-2h11.586l-4.293-4.293a1 1 0 010-1.414z"
              clip-rule="evenodd"
            >
            </path>
          </svg>
        </a>
      </div>

      <p class="text-sm text-gray-800 mb-4 leading-relaxed whitespace-pre-line">{@tweet.text}</p>

      <div :if={@tweet.classification_count >= 5} class="mb-4">
        <.ai_classification_comparison tweet={@tweet} />
      </div>

      <div :if={@tweet.classification_count >= 5} class="mb-4">
        <.voting_details tweet={@tweet} />
      </div>

      <div :if={@show_classification_buttons} class="pt-3 border-t border-gray-100">
        <.classification_buttons tweet_id={@tweet.tweet_id} />
      </div>
    </div>
    """
  end

  @doc """
  Renders AI classification comparison showing both models' predictions
  """
  attr :tweet, :map, required: true

  def ai_classification_comparison(assigns) do
    ~H"""
    <div class="bg-gray-50 rounded-lg p-3 space-y-3">
      <div class="flex items-center justify-between">
        <h4 class="text-sm font-medium text-gray-700">AI Model Comparison</h4>
        <span class={[
          "text-xs px-2 py-1 rounded-full font-medium",
          if(@tweet.agreement,
            do: "bg-green-100 text-green-800",
            else: "bg-red-100 text-red-800"
          )
        ]}>
          {if @tweet.agreement, do: "Agreement", else: "Disagreement"}
        </span>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
        <.model_prediction
          name="Inhouse model"
          is_prediction={@tweet.llama_is_prediction}
          prob_true={@tweet.llama_prob_true}
          color="green"
        />

        <.model_prediction
          name="OpenAI"
          is_prediction={@tweet.openai_is_prediction}
          prob_true={@tweet.openai_prob_true}
          color="blue"
        />
      </div>
    </div>
    """
  end

  @doc """
  Renders a single model's prediction details
  """
  attr :name, :string, required: true
  attr :is_prediction, :boolean
  attr :prob_true, :float
  attr :color, :string, default: "blue"

  def model_prediction(assigns) do
    ~H"""
    <div class="bg-white rounded border p-3">
      <div class="flex items-center justify-between mb-2">
        <span class={["text-sm font-medium", "text-#{@color}-700"]}>{@name}</span>
        <span class={[
          "text-xs px-2 py-1 rounded font-medium",
          if(@is_prediction,
            do: "bg-#{@color}-100 text-#{@color}-800",
            else: "bg-gray-100 text-gray-600"
          )
        ]}>
          {if @is_prediction, do: "Prediction", else: "Not Prediction"}
        </span>
      </div>

      <div class="text-center">
        <div class="text-2xl font-bold text-gray-900">
          {format_probability(@prob_true)}
        </div>
        <div class="text-xs text-gray-500">
          Prediction Confidence
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders voting details showing user classifications
  """
  attr :tweet, :map, required: true

  def voting_details(assigns) do
    ~H"""
    <div class="bg-blue-50 rounded-lg p-3">
      <div class="flex items-center justify-between mb-3">
        <h4 class="text-sm font-medium text-gray-700">Expert Classifications</h4>
        <span class="text-xs bg-blue-100 text-blue-800 px-2 py-1 rounded-full font-medium">
          {@tweet.classification_count}/5 votes
        </span>
      </div>

      <div :if={length(Map.get(@tweet, :classifications, [])) > 0} class="space-y-2">
        <div
          :for={classification <- Map.get(@tweet, :classifications, [])}
          class="flex items-center justify-between text-xs"
        >
          <span class="text-gray-600">{get_user_display(classification.user_email)}</span>
          <span class={[
            "px-2 py-1 rounded-full font-medium",
            if(classification.is_prediction,
              do: "bg-green-100 text-green-800",
              else: "bg-red-100 text-red-800"
            )
          ]}>
            {if classification.is_prediction, do: "👍 Prediction", else: "👎 Not Prediction"}
          </span>
        </div>
      </div>

      <div
        :if={@tweet.classification_count == 5 and @tweet.experts_is_prediction != nil}
        class="mt-3 pt-3 border-t border-blue-200"
      >
        <div class="flex items-center justify-between">
          <span class="text-sm font-medium text-gray-700">Expert Consensus:</span>
          <span class={[
            "text-sm px-3 py-1 rounded-full font-bold",
            if(@tweet.experts_is_prediction,
              do: "bg-green-200 text-green-900",
              else: "bg-red-200 text-red-900"
            )
          ]}>
            {if @tweet.experts_is_prediction, do: "✅ PREDICTION", else: "❌ NOT PREDICTION"}
          </span>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders classification buttons for user voting
  """
  attr :tweet_id, :string, required: true

  def classification_buttons(assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <span class="text-sm font-medium text-gray-700">Your Classification:</span>

      <button
        phx-click="classify_tweet"
        phx-value-tweet_id={@tweet_id}
        phx-value-is_prediction="true"
        class="bg-green-500 hover:bg-green-600 text-white text-sm font-medium py-2 px-4 rounded-lg transition-colors"
      >
        👍 Prediction
      </button>

      <button
        phx-click="classify_tweet"
        phx-value-tweet_id={@tweet_id}
        phx-value-is_prediction="false"
        class="bg-red-500 hover:bg-red-600 text-white text-sm font-medium py-2 px-4 rounded-lg transition-colors"
      >
        👎 Not Prediction
      </button>
    </div>
    """
  end

  @doc """
  Renders a header with title and refresh button for disagreement tweets
  """
  attr :title, :string, default: "Tweet Classification"
  attr :loading, :boolean, default: false

  def disagreement_header(assigns) do
    ~H"""
    <div class="flex justify-between items-center mb-6">
      <div>
        <h2 class="text-2xl font-bold text-gray-900">{@title}</h2>
        <p class="text-sm text-gray-600 mt-1">
          Help improve AI models by classifying tweets where models disagree
        </p>
      </div>
    </div>
    """
  end

  @doc """
  Renders statistics summary
  """
  attr :stats, :map, required: true

  def stats_summary(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
      <div class="bg-blue-50 rounded-lg p-4">
        <div class="text-2xl font-bold text-blue-600">{@stats.total_tweets}</div>
        <div class="text-sm text-blue-700">Total Tweets</div>
      </div>

      <div :for={{count, total} <- @stats.classification_counts} class="bg-green-50 rounded-lg p-4">
        <div class="text-2xl font-bold text-green-600">{total}</div>
        <div class="text-sm text-green-700">Classified by {count}</div>
      </div>
    </div>
    """
  end

  @doc """
  Renders filter controls
  """
  attr :filter_options, :map, required: true

  def filter_controls(assigns) do
    ~H"""
    <div class="bg-gray-50 rounded-lg p-4 mb-4">
      <h3 class="text-sm font-medium text-gray-700 mb-3">Filters</h3>

      <div class="flex items-center gap-4">
        <div class="flex items-center gap-2">
          <label class="text-sm text-gray-600">Probability Range:</label>
          <input
            type="range"
            min="0"
            max="1"
            step="0.1"
            value={elem(@filter_options.prob_range, 0)}
            phx-change="filter_prob_range"
            name="min"
            class="w-20"
          />
          <span class="text-xs text-gray-500">{elem(@filter_options.prob_range, 0)}</span>
          <span class="text-gray-400">-</span>
          <input
            type="range"
            min="0"
            max="1"
            step="0.1"
            value={elem(@filter_options.prob_range, 1)}
            phx-change="filter_prob_range"
            name="max"
            class="w-20"
          />
          <span class="text-xs text-gray-500">{elem(@filter_options.prob_range, 1)}</span>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions
  defp format_date(datetime) when is_struct(datetime, NaiveDateTime) do
    datetime
    |> NaiveDateTime.to_string()
    |> String.replace("T", " at ")
    |> String.slice(0, 19)
  end

  defp format_date(datetime_str) when is_binary(datetime_str) do
    case NaiveDateTime.from_iso8601(datetime_str) do
      {:ok, datetime} -> format_date(datetime)
      _ -> datetime_str
    end
  end

  defp format_date(_), do: "Unknown"

  defp format_probability(nil), do: "N/A"

  defp format_probability(prob) when is_float(prob) do
    "#{Float.round(prob * 100, 1)}%"
  end

  defp format_probability(_), do: "N/A"

  defp get_user_display(email) when is_binary(email) do
    email
    |> String.split("@")
    |> List.first()
    |> case do
      username when byte_size(username) > 12 ->
        String.slice(username, 0, 12) <> "..."

      username ->
        username
    end
  end

  defp get_user_display(_), do: "Unknown"
end
