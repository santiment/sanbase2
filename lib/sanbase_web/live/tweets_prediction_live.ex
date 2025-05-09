defmodule SanbaseWeb.TweetsPredictionLive do
  use SanbaseWeb, :live_view

  alias Sanbase.TweetsApi
  alias Sanbase.TweetPrediction
  import SanbaseWeb.TweetPredictionComponents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Initial fetch on page load
      send(self(), :fetch_tweets)
    end

    # Get tweet classification counts
    counts = TweetPrediction.get_counts()

    {:ok,
     assign(socket,
       tweets: [],
       loading: true,
       # Set to store interesting case IDs
       interesting_cases: MapSet.new(),
       # Set of already classified tweet IDs
       classified_tweet_ids: MapSet.new(),
       # Tweets after filtering out already classified ones
       filtered_tweets: [],
       # Statistics for classified tweets
       counts: counts
     )}
  end

  @impl true
  def handle_info(:fetch_tweets, socket) do
    # Get all classified tweet IDs from the database
    classified_tweet_ids = TweetPrediction.list_classified_tweet_ids()

    # Get tweet classification counts
    counts = TweetPrediction.get_counts()

    case TweetsApi.fetch_tweets(socket.assigns.current_user.email) do
      {:ok, tweets} ->
        # Filter out already classified tweets
        filtered_tweets =
          Enum.reject(tweets, fn tweet ->
            MapSet.member?(classified_tweet_ids, tweet["id"])
          end)

        {:noreply,
         assign(socket,
           tweets: tweets,
           filtered_tweets: filtered_tweets,
           classified_tweet_ids: classified_tweet_ids,
           loading: false,
           counts: counts
         )}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           tweets: [],
           filtered_tweets: [],
           loading: false,
           counts: counts
         )}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    send(self(), :fetch_tweets)
    {:noreply, assign(socket, loading: true)}
  end

  @impl true
  def handle_event("toggle_interesting", %{"id" => id}, socket) do
    interesting_cases = socket.assigns.interesting_cases

    # Toggle interesting case
    updated_cases =
      if MapSet.member?(interesting_cases, id) do
        MapSet.delete(interesting_cases, id)
      else
        MapSet.put(interesting_cases, id)
      end

    {:noreply, assign(socket, interesting_cases: updated_cases)}
  end

  @impl true
  def handle_event(
        "submit_classification",
        %{"id" => id, "prediction" => prediction, "interesting" => interesting},
        socket
      ) do
    submit_classification(id, prediction, interesting, socket)
  end

  @impl true
  def handle_event(
        "submit_classification",
        %{"id" => id, "prediction" => prediction},
        socket
      ) do
    # Check if this tweet ID is in the interesting cases
    is_interesting = MapSet.member?(socket.assigns.interesting_cases, id)
    interesting = if is_interesting, do: "true", else: "false"

    submit_classification(id, prediction, interesting, socket)
  end

  defp submit_classification(id, prediction, interesting, socket) do
    # Find the tweet in the tweets list
    tweet = Enum.find(socket.assigns.tweets, fn t -> t["id"] == id end)

    if tweet do
      # Convert string boolean to actual boolean
      is_interesting = interesting == "true"
      is_prediction = prediction == "prediction"

      # Create the classification record
      attrs = %{
        tweet_id: tweet["id"],
        timestamp: NaiveDateTime.from_iso8601!(tweet["timestamp"]),
        text: tweet["text"],
        url: tweet["url"],
        screen_name: tweet["screen_name"],
        is_prediction: is_prediction,
        is_interesting: is_interesting
      }

      case TweetPrediction.create(attrs) do
        {:ok, _prediction} ->
          # Update the classified tweet IDs
          classified_tweet_ids = MapSet.put(socket.assigns.classified_tweet_ids, id)

          # Filter out the newly classified tweet
          filtered_tweets = Enum.reject(socket.assigns.filtered_tweets, fn t -> t["id"] == id end)

          # Clear the interesting case for this tweet
          interesting_cases = MapSet.delete(socket.assigns.interesting_cases, id)

          # Update counts
          counts = TweetPrediction.get_counts()

          socket =
            assign(socket,
              classified_tweet_ids: classified_tweet_ids,
              filtered_tweets: filtered_tweets,
              interesting_cases: interesting_cases,
              counts: counts
            )

          {:noreply, put_flash(socket, :info, "Tweet classification saved successfully!")}

        {:error, changeset} ->
          errors =
            Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
              Enum.reduce(opts, msg, fn {key, value}, acc ->
                String.replace(acc, "%{#{key}}", to_string(value))
              end)
            end)

          error_msg = "Error saving classification: #{inspect(errors)}"
          {:noreply, put_flash(socket, :error, error_msg)}
      end
    else
      {:noreply, put_flash(socket, :error, "Tweet not found!")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <div class="bg-white p-4 rounded-lg shadow">
        <.tweet_header title="Tweet Predictions Classifier" loading={@loading} />

        <div class="flex justify-between text-sm text-gray-700 mb-4 px-2">
          <div>Total Classified: <span class="font-semibold">{@counts.total}</span></div>
          <div>
            Predictions: <span class="font-semibold text-green-600">{@counts.predictions}</span>
          </div>
          <div>
            Not Predictions: <span class="font-semibold text-red-600">{@counts.not_predictions}</span>
          </div>
        </div>

        <%= if @loading do %>
          <.loading_indicator />
        <% else %>
          <%= if Enum.empty?(@filtered_tweets) do %>
            <.empty_state />
          <% else %>
            <div class="space-y-4">
              <.tweet_card
                :for={tweet <- @filtered_tweets}
                tweet={tweet}
                interesting_case={MapSet.member?(@interesting_cases, tweet["id"])}
              />
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end
