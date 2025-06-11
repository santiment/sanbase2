defmodule Sanbase.DisagreementTweets.TestData do
  @moduledoc """
  Module for populating test data for disagreement tweets
  """

  alias Sanbase.{DisagreementTweets, TweetsApi}

  @doc """
  Populates test disagreement tweets by fetching tweets and classifying them one by one

  ## Options

    * `:hours` - Number of hours to look back for tweets (default: 24)
    * `:size` - Maximum number of tweets to fetch (default: 50) - ignored when influencers: true
    * `:influencers` - If true, fetches from crypto influencers endpoint instead of recent tweets (default: false)

  ## Examples

      iex> Sanbase.DisagreementTweets.TestData.populate()
      {:ok, %{fetched: 50, classified: 45, stored: 3, skipped: 1, errors: 0}}

      iex> Sanbase.DisagreementTweets.TestData.populate(hours: 12, size: 100)
      {:ok, %{fetched: 100, classified: 95, stored: 15, skipped: 5, errors: 1}}

      iex> Sanbase.DisagreementTweets.TestData.populate(influencers: true, hours: 6)
      {:ok, %{fetched: 25, classified: 23, stored: 8, skipped: 2, errors: 0}}
  """
  def populate(opts \\ []) do
    hours = Keyword.get(opts, :hours, 24)
    size = Keyword.get(opts, :size, 50)
    influencers = Keyword.get(opts, :influencers, false)

    IO.puts("🔍 Fetching #{if influencers, do: "crypto influencer", else: "recent"} tweets...")

    result =
      if influencers do
        TweetsApi.fetch_influencer_tweets(hours: hours)
      else
        TweetsApi.fetch_recent_tweets(hours: hours, size: size)
      end

    case result do
      {:ok, tweets} ->
        IO.puts("✅ Fetched #{length(tweets)} tweets")
        IO.puts("🤖 Starting classification and storage...")
        IO.puts("")

        results = %{
          fetched: length(tweets),
          classified: 0,
          stored: 0,
          skipped: 0,
          errors: 0
        }

        final_results =
          tweets
          |> Enum.with_index(1)
          |> Enum.reduce(results, fn {tweet, index}, acc ->
            IO.write("[#{index}/#{length(tweets)}] ")

            case TweetsApi.classify_tweet(tweet["text"]) do
              {:ok, classification} ->
                acc = %{acc | classified: acc.classified + 1}

                # Show classification times
                openai_time = get_in(classification, ["openai", "time_seconds"]) || 0
                llama_time = get_in(classification, ["llama_inhouse", "time_seconds"]) || 0

                IO.write(
                  "(OpenAI: #{Float.round(openai_time, 2)}s, Inhouse: #{Float.round(llama_time, 2)}s) "
                )

                # Create full classified tweet object
                classified_tweet = Map.put(tweet, "classification", classification)

                # Check if this tweet should be stored (disagreement criteria)
                should_store =
                  classification["agreement"] == false or
                    prob_in_range?(classification, 0.3, 0.7)

                if should_store do
                  case store_classified_tweet(classified_tweet) do
                    {:ok, _tweet} ->
                      IO.puts("✅ Stored disagreement tweet")
                      %{acc | stored: acc.stored + 1}

                    {:error, :already_exists} ->
                      IO.puts("⏭️  Skipped (already exists)")
                      %{acc | skipped: acc.skipped + 1}

                    {:error, _reason} ->
                      IO.puts("❌ Error storing tweet")
                      %{acc | errors: acc.errors + 1}
                  end
                else
                  IO.puts("📊 Classified but no disagreement")
                  acc
                end

              {:error, reason} ->
                IO.puts("❌ Classification failed: #{inspect(reason)}")
                %{acc | errors: acc.errors + 1}
            end
          end)

        IO.puts("")
        IO.puts("🎉 Completed! Results:")
        IO.puts("   📥 Fetched: #{final_results.fetched}")
        IO.puts("   🤖 Classified: #{final_results.classified}")
        IO.puts("   💾 Stored: #{final_results.stored}")
        IO.puts("   ⏭️  Skipped: #{final_results.skipped}")
        IO.puts("   ❌ Errors: #{final_results.errors}")
        IO.puts("")
        IO.puts("Check the admin panel at /admin/disagreement_tweets")

        {:ok, final_results}

      {:error, reason} ->
        IO.puts("❌ Error fetching tweets: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp store_classified_tweet(classified_tweet) do
    tweet_with_classification = Map.merge(classified_tweet, classified_tweet["classification"])

    attrs = %{
      tweet_id: classified_tweet["id"],
      timestamp: parse_timestamp(classified_tweet["timestamp"]),
      screen_name: classified_tweet["screen_name"],
      text: classified_tweet["text"],
      url: classified_tweet["url"],
      agreement: tweet_with_classification["agreement"],
      openai_is_prediction: get_in(tweet_with_classification, ["openai", "is_prediction"]),
      openai_prob_true: get_in(tweet_with_classification, ["openai", "probability_true"]),
      openai_prob_false: get_in(tweet_with_classification, ["openai", "probability_false"]),
      openai_prob_other: get_in(tweet_with_classification, ["openai", "probability_other"]),
      openai_time_seconds: get_in(tweet_with_classification, ["openai", "time_seconds"]),
      llama_is_prediction: get_in(tweet_with_classification, ["llama_inhouse", "is_prediction"]),
      llama_prob_true: get_in(tweet_with_classification, ["llama_inhouse", "probability_true"]),
      llama_prob_false: get_in(tweet_with_classification, ["llama_inhouse", "probability_false"]),
      llama_prob_other: get_in(tweet_with_classification, ["llama_inhouse", "probability_other"]),
      llama_time_seconds: get_in(tweet_with_classification, ["llama_inhouse", "time_seconds"])
    }

    case DisagreementTweets.create_disagreement_tweet(attrs) do
      {:ok, tweet} ->
        {:ok, tweet}

      {:error, changeset} ->
        if changeset.errors[:tweet_id] do
          {:error, :already_exists}
        else
          {:error, changeset}
        end
    end
  end

  defp prob_in_range?(classification, min_prob, max_prob) do
    openai_prob = get_in(classification, ["openai", "probability_true"])
    llama_prob = get_in(classification, ["llama_inhouse", "probability_true"])

    (openai_prob && openai_prob >= min_prob && openai_prob <= max_prob) or
      (llama_prob && llama_prob >= min_prob && llama_prob <= max_prob)
  end

  defp parse_timestamp(timestamp_str) do
    case DateTime.from_iso8601(timestamp_str <> "Z") do
      {:ok, datetime, _offset} ->
        DateTime.to_naive(datetime)

      _ ->
        case NaiveDateTime.from_iso8601(timestamp_str) do
          {:ok, naive_datetime} -> naive_datetime
          _ -> NaiveDateTime.utc_now()
        end
    end
  end
end
