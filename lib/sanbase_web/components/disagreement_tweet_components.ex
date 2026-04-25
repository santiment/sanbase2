defmodule SanbaseWeb.DisagreementTweetComponents do
  use Phoenix.Component

  @doc """
  Renders a disagreement tweet card with AI classification details and voting buttons
  """
  attr :tweet, :map, required: true
  attr :show_classification_buttons, :boolean, default: false
  attr :show_results, :boolean, default: false
  attr :show_asset_direction_form, :boolean, default: false
  attr :user_id, :integer, required: true
  attr :rest, :global

  def disagreement_tweet_card(assigns) do
    ~H"""
    <div
      class="card bg-base-100 border border-base-300 p-4"
      id={"disagreement-tweet-#{@tweet.tweet_id}"}
      {@rest}
    >
      <div class="flex justify-between items-start mb-3">
        <div class="flex items-center gap-3 flex-wrap">
          <span class="font-bold text-primary text-sm">@{@tweet.screen_name}</span>
          <span class="text-xs text-base-content/60">{format_date(@tweet.timestamp)}</span>
          <span class="badge badge-sm badge-secondary">
            {@tweet.classification_count} {if @tweet.classification_count == 1,
              do: "person",
              else: "people"} classified
          </span>
          <span
            :if={@tweet.classification_count >= 5}
            class={[
              "badge badge-sm",
              if(@tweet.experts_is_prediction, do: "badge-success", else: "badge-error")
            ]}
          >
            {if @tweet.experts_is_prediction, do: "PREDICTION", else: "NOT PREDICTION"}
          </span>
        </div>

        <a
          href={@tweet.url}
          target="_blank"
          rel="noopener noreferrer"
          class="link link-primary text-xs flex items-center gap-1"
        >
          <span>View on X</span>
          <svg class="size-3" fill="currentColor" viewBox="0 0 20 20">
            <path
              fill-rule="evenodd"
              d="M10.293 3.293a1 1 0 011.414 0l6 6a1 1 0 010 1.414l-6 6a1 1 0 01-1.414-1.414L14.586 11H3a1 1 0 110-2h11.586l-4.293-4.293a1 1 0 010-1.414z"
              clip-rule="evenodd"
            >
            </path>
          </svg>
        </a>
      </div>

      <p class="text-sm mb-4 leading-relaxed whitespace-pre-line">{@tweet.text}</p>

      <div :if={@show_results or @tweet.classification_count >= 5} class="mb-4">
        <.ai_classification_comparison tweet={@tweet} />
      </div>

      <div :if={@show_results or @tweet.classification_count >= 5} class="mb-4">
        <.voting_details tweet={@tweet} />
      </div>

      <div :if={@show_asset_direction_form} class="mb-4">
        <.asset_direction_display_or_form tweet={@tweet} />
      </div>

      <div :if={@show_classification_buttons} class="pt-3 border-t border-base-300">
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
    <div class="bg-base-200 rounded-box p-3 space-y-3">
      <div class="flex items-center justify-between">
        <h4 class="text-sm font-medium">AI Model Comparison</h4>
        <span class={[
          "badge badge-sm",
          if(@tweet.agreement, do: "badge-success", else: "badge-error")
        ]}>
          {if @tweet.agreement, do: "Agreement", else: "Disagreement"}
        </span>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
        <.model_prediction
          name="Inhouse model"
          is_prediction={@tweet.llama_is_prediction}
          prob_true={@tweet.llama_prob_true}
          variant="success"
        />

        <.model_prediction
          name="OpenAI"
          is_prediction={@tweet.openai_is_prediction}
          prob_true={@tweet.openai_prob_true}
          variant="info"
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
  attr :variant, :string, default: "info"

  def model_prediction(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-box border border-base-300 p-3">
      <div class="flex items-center justify-between mb-2">
        <span class={["text-sm font-medium", "text-#{@variant}"]}>{@name}</span>
        <span class={[
          "badge badge-sm",
          if(@is_prediction, do: "badge-#{@variant}", else: "badge-ghost")
        ]}>
          {if @is_prediction, do: "Prediction", else: "Not Prediction"}
        </span>
      </div>

      <div class="text-center">
        <div class="text-2xl font-bold">
          {format_probability(@prob_true)}
        </div>
        <div class="text-xs text-base-content/60">
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
    <div class="bg-info/10 rounded-box p-3">
      <div class="flex items-center justify-between mb-3">
        <h4 class="text-sm font-medium">Expert Classifications</h4>
        <span class="badge badge-sm badge-info">{@tweet.classification_count}/5 votes</span>
      </div>

      <div :if={length(Map.get(@tweet, :classifications, [])) > 0} class="space-y-2">
        <div
          :for={classification <- Map.get(@tweet, :classifications, [])}
          class="flex items-center justify-between text-xs"
        >
          <span class="text-base-content/70">{get_user_display(classification.user_email)}</span>
          <span class={[
            "badge badge-sm",
            if(classification.is_prediction, do: "badge-success", else: "badge-error")
          ]}>
            {if classification.is_prediction, do: "Prediction", else: "Not Prediction"}
          </span>
        </div>
      </div>

      <div
        :if={@tweet.classification_count >= 5 and @tweet.experts_is_prediction != nil}
        class="mt-3 pt-3 border-t border-info/30"
      >
        <div class="flex items-center justify-between">
          <span class="text-sm font-medium">Expert Consensus:</span>
          <span class={[
            "badge",
            if(@tweet.experts_is_prediction, do: "badge-success", else: "badge-error")
          ]}>
            {if @tweet.experts_is_prediction, do: "PREDICTION", else: "NOT PREDICTION"}
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
      <span class="text-sm font-medium">Your Classification:</span>

      <button
        phx-click="classify_tweet"
        phx-value-tweet_id={@tweet_id}
        phx-value-is_prediction="true"
        class="btn btn-sm btn-success"
      >
        Prediction
      </button>

      <button
        phx-click="classify_tweet"
        phx-value-tweet_id={@tweet_id}
        phx-value-is_prediction="false"
        class="btn btn-sm btn-error"
      >
        Not Prediction
      </button>
    </div>
    """
  end

  @doc """
  Renders asset direction information or form to add it
  """
  attr :tweet, :map, required: true

  def asset_direction_display_or_form(assigns) do
    ~H"""
    <div class="bg-warning/10 rounded-box p-4">
      <h4 class="text-sm font-medium mb-3">Asset Direction Information</h4>

      <div :if={has_asset_direction_info?(@tweet)} class="space-y-2">
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div :if={@tweet.prediction_direction} class="text-center">
            <span class="text-xs text-base-content/60 block">Direction</span>
            <span class={["badge mt-1", direction_color(@tweet.prediction_direction)]}>
              {direction_display(@tweet.prediction_direction)}
            </span>
          </div>

          <div :if={@tweet.base_asset} class="text-center">
            <span class="text-xs text-base-content/60 block">Base Asset</span>
            <span class="badge badge-info mt-1">{@tweet.base_asset}</span>
          </div>

          <div :if={@tweet.quote_asset} class="text-center">
            <span class="text-xs text-base-content/60 block">Quote Asset</span>
            <span class="badge badge-ghost mt-1">{@tweet.quote_asset}</span>
          </div>
        </div>
      </div>

      <form
        :if={!has_asset_direction_info?(@tweet)}
        phx-submit="add_asset_direction"
        phx-hook="TickerAutocomplete"
        id={"asset_direction_form_#{@tweet.tweet_id}"}
        class="space-y-4"
      >
        <input type="hidden" name="tweet_id" value={@tweet.tweet_id} />

        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <fieldset class="fieldset">
            <legend class="fieldset-legend">Prediction Direction</legend>
            <select name="prediction_direction" class="select select-sm w-full">
              <option value="">Select direction...</option>
              <option value="up">Up</option>
              <option value="down">Down</option>
              <option value="side">Sideways</option>
              <option value="other">Other</option>
            </select>
          </fieldset>

          <fieldset class="fieldset relative">
            <legend class="fieldset-legend">Base Asset (optional)</legend>
            <input
              type="text"
              name="base_asset"
              placeholder="e.g., BTC, ETH..."
              class="input input-sm w-full"
              phx-change="search_tickers"
              phx-debounce="300"
              autocomplete="off"
              id={"base_asset_#{@tweet.tweet_id}"}
            />
            <div
              id={"base_asset_suggestions_#{@tweet.tweet_id}"}
              class="absolute z-50 w-full mt-1 bg-base-100 border border-base-300 rounded-box shadow-xl max-h-48 overflow-y-auto hidden"
            >
            </div>
          </fieldset>

          <fieldset class="fieldset relative">
            <legend class="fieldset-legend">Quote Asset (optional)</legend>
            <input
              type="text"
              name="quote_asset"
              placeholder="USD (default), EUR..."
              class="input input-sm w-full"
              phx-change="search_tickers"
              phx-debounce="300"
              autocomplete="off"
              id={"quote_asset_#{@tweet.tweet_id}"}
            />
            <div
              id={"quote_asset_suggestions_#{@tweet.tweet_id}"}
              class="absolute z-50 w-full mt-1 bg-base-100 border border-base-300 rounded-box shadow-xl max-h-48 overflow-y-auto hidden"
            >
            </div>
          </fieldset>
        </div>

        <div class="flex justify-end">
          <button type="submit" class="btn btn-sm btn-primary">
            Add Asset Direction
          </button>
        </div>
      </form>
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
        <h2 class="text-2xl font-bold">{@title}</h2>
        <p class="text-sm text-base-content/70 mt-1">
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
      <div class="card bg-info/10 border border-info/30 p-4">
        <div class="text-2xl font-bold text-info">{@stats.total_tweets}</div>
        <div class="text-sm text-info">Total Tweets</div>
      </div>

      <div
        :for={{count, total} <- @stats.classification_counts}
        class="card bg-success/10 border border-success/30 p-4"
      >
        <div class="text-2xl font-bold text-success">{total}</div>
        <div class="text-sm text-success">Classified by {count}</div>
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
    <div class="bg-base-200 rounded-box p-4 mb-4">
      <h3 class="text-sm font-medium mb-3">Filters</h3>

      <div class="flex items-center gap-4">
        <div class="flex items-center gap-2">
          <label class="text-sm text-base-content/70">Probability Range:</label>
          <input
            type="range"
            min="0"
            max="1"
            step="0.1"
            value={elem(@filter_options.prob_range, 0)}
            phx-change="filter_prob_range"
            name="min"
            class="range range-xs w-20"
          />
          <span class="text-xs text-base-content/60">{elem(@filter_options.prob_range, 0)}</span>
          <span class="text-base-content/40">-</span>
          <input
            type="range"
            min="0"
            max="1"
            step="0.1"
            value={elem(@filter_options.prob_range, 1)}
            phx-change="filter_prob_range"
            name="max"
            class="range range-xs w-20"
          />
          <span class="text-xs text-base-content/60">{elem(@filter_options.prob_range, 1)}</span>
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

  defp has_asset_direction_info?(tweet) do
    tweet.prediction_direction != nil and tweet.prediction_direction != ""
  end

  defp direction_display("up"), do: "Up"
  defp direction_display("down"), do: "Down"
  defp direction_display("side"), do: "Sideways"
  defp direction_display("other"), do: "Other"
  defp direction_display(_), do: "N/A"

  defp direction_color("up"), do: "badge-success"
  defp direction_color("down"), do: "badge-error"
  defp direction_color("side"), do: "badge-warning"
  defp direction_color("other"), do: "badge-secondary"
  defp direction_color(_), do: "badge-ghost"
end
