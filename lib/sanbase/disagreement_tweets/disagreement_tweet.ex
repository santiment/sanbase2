defmodule Sanbase.DisagreementTweets.ClassifiedTweet do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.DisagreementTweets.TweetClassification

  @table_name "classified_tweets"

  schema @table_name do
    field(:tweet_id, :string)
    field(:timestamp, :naive_datetime)
    field(:screen_name, :string)
    field(:text, :string)
    field(:url, :string)
    field(:agreement, :boolean)
    field(:review_required, :boolean, default: false)

    # OpenAI model fields
    field(:openai_is_prediction, :boolean)
    field(:openai_prob_true, :float)
    field(:openai_prob_false, :float)
    field(:openai_prob_other, :float)
    field(:openai_time_seconds, :float)

    # Llama model fields
    field(:llama_is_prediction, :boolean)
    field(:llama_prob_true, :float)
    field(:llama_prob_false, :float)
    field(:llama_prob_other, :float)
    field(:llama_time_seconds, :float)

    field(:classification_count, :integer, default: 0)
    field(:experts_is_prediction, :boolean)

    has_many(:classifications, TweetClassification, foreign_key: :classified_tweet_id)

    timestamps()
  end

  @required_fields [
    :tweet_id,
    :timestamp,
    :screen_name,
    :text,
    :url,
    :agreement,
    :review_required
  ]

  @optional_fields [
    :openai_is_prediction,
    :openai_prob_true,
    :openai_prob_false,
    :openai_prob_other,
    :openai_time_seconds,
    :llama_is_prediction,
    :llama_prob_true,
    :llama_prob_false,
    :llama_prob_other,
    :llama_time_seconds,
    :classification_count,
    :experts_is_prediction
  ]

  def changeset(tweet, attrs) do
    tweet
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:tweet_id, name: :disagreement_tweets_tweet_id_index)
    |> validate_inclusion(:agreement, [true, false])
    |> validate_inclusion(:review_required, [true, false])
    |> validate_number(:classification_count, greater_than_or_equal_to: 0)
  end

  # Query helpers for disagreement tweets only
  def disagreement_tweets(query \\ __MODULE__) do
    from(q in query, where: q.review_required == true)
  end

  def not_classified_by_user(query \\ disagreement_tweets(), user_id) do
    from(q in query,
      left_join: tc in TweetClassification,
      on: tc.classified_tweet_id == q.id and tc.user_id == ^user_id,
      where: is_nil(tc.id)
    )
  end

  def classified_by_user(query \\ disagreement_tweets(), user_id) do
    from(q in query,
      join: tc in TweetClassification,
      on: tc.classified_tweet_id == q.id and tc.user_id == ^user_id
    )
  end

  def by_classification_count(query \\ disagreement_tweets(), count) do
    from(q in query, where: q.classification_count == ^count)
  end

  def in_prob_range(query, min_prob, max_prob) do
    from(q in query,
      where:
        (q.openai_prob_true >= ^min_prob and q.openai_prob_true <= ^max_prob) or
          (q.llama_prob_true >= ^min_prob and q.llama_prob_true <= ^max_prob)
    )
  end

  def order_by_timestamp(query \\ __MODULE__) do
    from(q in query, order_by: [desc: q.timestamp])
  end
end
