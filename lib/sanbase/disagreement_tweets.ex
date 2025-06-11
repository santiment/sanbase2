defmodule Sanbase.DisagreementTweets do
  @moduledoc """
  Context for managing tweets with AI classification disagreement
  """

  import Ecto.Query
  alias Sanbase.Repo
  alias Sanbase.DisagreementTweets.{DisagreementTweet, TweetClassification}

  @doc """
  Creates a disagreement tweet record
  """
  def create_disagreement_tweet(attrs) do
    %DisagreementTweet{}
    |> DisagreementTweet.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a disagreement tweet by tweet ID
  """
  def get_by_tweet_id(tweet_id) do
    Repo.get_by(DisagreementTweet, tweet_id: tweet_id)
  end

  @doc """
  Lists disagreement tweets with optional filters
  """
  def list_disagreement_tweets(opts \\ []) do
    DisagreementTweet
    |> apply_filters(opts)
    |> DisagreementTweet.order_by_timestamp()
    |> Repo.all()
  end

  @doc """
  Gets tweets not classified by the user
  """
  def list_not_classified_by_user(user_id, opts \\ []) do
    DisagreementTweet
    |> DisagreementTweet.not_classified_by_user(user_id)
    |> apply_filters(opts)
    |> DisagreementTweet.order_by_timestamp()
    |> Repo.all()
    |> add_user_classification_status(user_id)
  end

  @doc """
  Gets tweets classified by the user
  """
  def list_classified_by_user(user_id, opts \\ []) do
    DisagreementTweet
    |> DisagreementTweet.classified_by_user(user_id)
    |> apply_filters(opts)
    |> DisagreementTweet.order_by_timestamp()
    |> preload([:classifications])
    |> Repo.all()
    |> add_user_classification_status(user_id)
  end

  @doc """
  Gets tweets by classification count
  """
  def list_by_classification_count(count, opts \\ []) when is_integer(count) and is_list(opts) do
    DisagreementTweet
    |> DisagreementTweet.by_classification_count(count)
    |> apply_filters(opts)
    |> DisagreementTweet.order_by_timestamp()
    |> Repo.all()
  end

  @doc """
  Gets tweets by classification count with user status
  """
  def list_by_classification_count_with_user_status(count, user_id, opts \\ []) do
    DisagreementTweet
    |> DisagreementTweet.by_classification_count(count)
    |> apply_filters(opts)
    |> DisagreementTweet.order_by_timestamp()
    |> Repo.all()
    |> add_user_classification_status(user_id)
  end

  @doc """
  Creates a tweet classification
  """
  def create_classification(attrs) do
    %TweetClassification{}
    |> TweetClassification.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, classification} ->
        update_classification_count(classification.disagreement_tweet_id)
        {:ok, classification}

      error ->
        error
    end
  end

  @doc """
  Gets a user's classification for a specific tweet
  """
  def get_user_classification(tweet_id, user_id) do
    query =
      from(tc in TweetClassification,
        join: dt in DisagreementTweet,
        on: tc.disagreement_tweet_id == dt.id,
        where: dt.tweet_id == ^tweet_id and tc.user_id == ^user_id
      )

    Repo.one(query)
  end

  @doc """
  Checks if user has classified a specific tweet
  """
  def user_has_classified?(tweet_id, user_id) do
    get_user_classification(tweet_id, user_id) != nil
  end

  @doc """
  Gets statistics about disagreement tweets
  """
  def get_stats do
    total_tweets = Repo.aggregate(DisagreementTweet, :count, :id)

    classification_counts =
      from(dt in DisagreementTweet,
        group_by: dt.classification_count,
        select: {dt.classification_count, count(dt.id)}
      )
      |> Repo.all()
      |> Map.new()

    %{
      total_tweets: total_tweets,
      classification_counts: classification_counts
    }
  end

  @doc """
  Gets tab counts for a specific user
  """
  def get_tab_counts(user_id) do
    # Count of tweets not classified by user
    not_classified_by_me =
      DisagreementTweet
      |> DisagreementTweet.not_classified_by_user(user_id)
      |> Repo.aggregate(:count, :id)

    # Count of tweets classified by user
    classified_by_me =
      DisagreementTweet
      |> DisagreementTweet.classified_by_user(user_id)
      |> Repo.aggregate(:count, :id)

    # Count of completed tweets (classified by 5 people)
    completed =
      DisagreementTweet
      |> DisagreementTweet.by_classification_count(5)
      |> Repo.aggregate(:count, :id)

    %{
      not_classified_by_me: not_classified_by_me,
      classified_by_me: classified_by_me,
      completed: completed
    }
  end

  @doc """
  Processes and stores tweets from API with classification results
  """
  def process_and_store_tweets(tweets_with_classification) do
    Enum.each(tweets_with_classification, fn tweet_data ->
      # Only store tweets with disagreement = false or prob_true in [0.3, 0.7]
      if should_store_tweet?(tweet_data) do
        store_disagreement_tweet(tweet_data)
      end
    end)
  end

  defp should_store_tweet?(%{"agreement" => false}), do: true

  defp should_store_tweet?(%{"openai" => %{"probability_true" => prob}})
       when prob >= 0.3 and prob <= 0.7,
       do: true

  defp should_store_tweet?(%{"llama_inhouse" => %{"probability_true" => prob}})
       when prob >= 0.3 and prob <= 0.7,
       do: true

  defp should_store_tweet?(_), do: false

  defp store_disagreement_tweet(tweet_data) do
    attrs = %{
      tweet_id: tweet_data["id"],
      timestamp: parse_timestamp(tweet_data["timestamp"]),
      screen_name: tweet_data["screen_name"],
      text: tweet_data["text"],
      url: tweet_data["url"],
      agreement: tweet_data["agreement"],
      openai_is_prediction: get_in(tweet_data, ["openai", "is_prediction"]),
      openai_prob_true: get_in(tweet_data, ["openai", "probability_true"]),
      openai_prob_false: get_in(tweet_data, ["openai", "probability_false"]),
      openai_prob_other: get_in(tweet_data, ["openai", "probability_other"]),
      openai_time_seconds: get_in(tweet_data, ["openai", "time_seconds"]),
      llama_is_prediction: get_in(tweet_data, ["llama_inhouse", "is_prediction"]),
      llama_prob_true: get_in(tweet_data, ["llama_inhouse", "probability_true"]),
      llama_prob_false: get_in(tweet_data, ["llama_inhouse", "probability_false"]),
      llama_prob_other: get_in(tweet_data, ["llama_inhouse", "probability_other"]),
      llama_time_seconds: get_in(tweet_data, ["llama_inhouse", "time_seconds"])
    }

    create_disagreement_tweet(attrs)
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

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn {key, value}, query ->
      case key do
        :prob_range ->
          {min_prob, max_prob} = value
          DisagreementTweet.in_prob_range(query, min_prob, max_prob)

        :limit ->
          from(q in query, limit: ^value)

        _ ->
          query
      end
    end)
  end

  defp update_classification_count(disagreement_tweet_id) do
    count =
      Repo.aggregate(
        from(tc in TweetClassification, where: tc.disagreement_tweet_id == ^disagreement_tweet_id),
        :count,
        :id
      )

    from(dt in DisagreementTweet, where: dt.id == ^disagreement_tweet_id)
    |> Repo.update_all(set: [classification_count: count])
  end

  defp add_user_classification_status(tweets, user_id) do
    tweet_ids = Enum.map(tweets, & &1.tweet_id)

    classified_tweet_ids =
      from(tc in TweetClassification,
        join: dt in DisagreementTweet,
        on: tc.disagreement_tweet_id == dt.id,
        where: dt.tweet_id in ^tweet_ids and tc.user_id == ^user_id,
        select: dt.tweet_id
      )
      |> Repo.all()
      |> MapSet.new()

    Enum.map(tweets, fn tweet ->
      user_has_classified = MapSet.member?(classified_tweet_ids, tweet.tweet_id)
      Map.put(tweet, :user_has_classified, user_has_classified)
    end)
  end
end
