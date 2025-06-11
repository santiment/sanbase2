defmodule SanbaseWeb.DisagreementTweetsLive do
  use SanbaseWeb, :live_view

  alias Sanbase.DisagreementTweets
  import SanbaseWeb.DisagreementTweetComponents

  @tabs [
    {:not_classified_by_me, "Not classified by me"},
    {:classified_by_me, "Classified by me"},
    {:completed, "Completed (5 people classified)"}
  ]

  defp tabs, do: @tabs

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       tweets: [],
       loading: true,
       active_tab: :not_classified_by_me,
       tab_counts: %{not_classified_by_me: 0, classified_by_me: 0, completed: 0},
       filter_options: %{prob_range: {0.3, 0.7}}
     )}
  end

  @impl true
  def handle_params(%{"tab" => tab}, _url, socket) do
    tab_atom = String.to_existing_atom(tab)

    if connected?(socket) do
      send(self(), {:load_tweets, tab_atom})
    end

    {:noreply, assign(socket, active_tab: tab_atom, loading: true)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    if connected?(socket) do
      send(self(), {:load_tweets, :not_classified_by_me})
    end

    {:noreply, assign(socket, active_tab: :not_classified_by_me, loading: true)}
  end

  @impl true
  def handle_info({:load_tweets, tab}, socket) do
    user_id = socket.assigns.current_user.id

    tweets =
      case tab do
        :not_classified_by_me ->
          DisagreementTweets.list_not_classified_by_user(user_id, limit: 50)
          |> Enum.sort_by(& &1.classification_count, :desc)

        :classified_by_me ->
          DisagreementTweets.list_classified_by_user(user_id, limit: 50)
          |> Enum.sort_by(& &1.classification_count, :desc)

        :completed ->
          DisagreementTweets.list_by_classification_count_with_user_status(5, user_id, limit: 50)
          |> Enum.sort_by(& &1.classification_count, :desc)
      end

    tab_counts = DisagreementTweets.get_tab_counts(user_id)

    {:noreply,
     assign(socket,
       tweets: tweets,
       tab_counts: tab_counts,
       loading: false
     )}
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/disagreement_tweets?tab=#{tab}")}
  end

  @impl true
  def handle_event(
        "classify_tweet",
        %{"tweet_id" => tweet_id, "is_prediction" => is_prediction},
        socket
      ) do
    user_id = socket.assigns.current_user.id

    # Find the tweet
    tweet = Enum.find(socket.assigns.tweets, fn t -> t.tweet_id == tweet_id end)

    if tweet do
      attrs = %{
        disagreement_tweet_id: tweet.id,
        user_id: user_id,
        is_prediction: is_prediction == "true",
        classified_at: NaiveDateTime.utc_now()
      }

      case DisagreementTweets.create_classification(attrs) do
        {:ok, _classification} ->
          # Reload tweets for current tab
          send(self(), {:load_tweets, socket.assigns.active_tab})
          {:noreply, put_flash(socket, :info, "Tweet classified successfully!")}

        {:error, changeset} ->
          error_msg = extract_error_message(changeset)
          {:noreply, put_flash(socket, :error, "Error classifying tweet: #{error_msg}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Tweet not found")}
    end
  end

  @impl true
  def handle_event("filter_prob_range", %{"min" => min_str, "max" => max_str}, socket) do
    min_prob = String.to_float(min_str)
    max_prob = String.to_float(max_str)

    filter_options = Map.put(socket.assigns.filter_options, :prob_range, {min_prob, max_prob})

    # Reload with new filter
    send(self(), {:load_tweets, socket.assigns.active_tab})

    {:noreply, assign(socket, filter_options: filter_options, loading: true)}
  end

  defp extract_error_message(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Map.values()
    |> List.flatten()
    |> Enum.join(", ")
  end

  defp get_tab_count(tab_counts, tab) do
    Map.get(tab_counts, tab, 0)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto">
      <div class="bg-white p-4 rounded-lg shadow">
        <.disagreement_header title="Tweet Classification" loading={@loading} />

        <.tab_navigation active_tab={@active_tab} tabs={tabs()} tab_counts={@tab_counts} />

        <div :if={@loading} class="flex justify-center items-center h-16">
          <p class="text-sm text-gray-500">Loading tweets...</p>
        </div>

        <div
          :if={!@loading and Enum.empty?(@tweets)}
          class="flex flex-col items-center justify-center h-32 text-center"
        >
          <p class="text-sm text-gray-500 mb-2">No tweets available for this category</p>
          <button
            class="bg-blue-500 hover:bg-blue-700 text-white text-xs font-bold py-1 px-2 rounded"
            phx-click="refresh"
          >
            Refresh Data
          </button>
        </div>

        <div :if={!@loading and not Enum.empty?(@tweets)} class="space-y-4 mt-4">
          <.disagreement_tweet_card
            :for={tweet <- @tweets}
            tweet={tweet}
            show_classification_buttons={@active_tab == :not_classified_by_me}
            user_id={@current_user.id}
          />
        </div>
      </div>
    </div>
    """
  end

  defp tab_navigation(assigns) do
    ~H"""
    <div class="border-b border-gray-200 mb-4">
      <nav class="-mb-px flex space-x-8">
        <button
          :for={{tab_key, tab_label} <- @tabs}
          phx-click="change_tab"
          phx-value-tab={tab_key}
          class={[
            "py-2 px-1 border-b-2 font-medium text-sm",
            if(@active_tab == tab_key,
              do: "border-blue-500 text-blue-600",
              else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
            )
          ]}
        >
          {tab_label}
          <span class="ml-2 bg-gray-100 text-gray-600 py-0.5 px-2 rounded-full text-xs">
            {get_tab_count(@tab_counts, tab_key)}
          </span>
        </button>
      </nav>
    </div>
    """
  end
end
