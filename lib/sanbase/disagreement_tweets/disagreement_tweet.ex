defmodule Sanbase.DisagreementTweets.DisagreementTweet do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.DisagreementTweets.TweetClassification

  schema "disagreement_tweets" do
    field(:tweet_id, :string)
    field(:timestamp, :utc_datetime)
    field(:screen_name, :string)
    field(:text, :string)
    field(:url, :string)
    field(:agreement, :boolean, default: false)
    field(:openai_is_prediction, :boolean)
    field(:openai_prob_true, :float)
    field(:openai_prob_false, :float)
    field(:openai_prob_other, :float)
    field(:openai_time_seconds, :float)
    field(:llama_is_prediction, :boolean)
    field(:llama_prob_true, :float)
    field(:llama_prob_false, :float)
    field(:llama_prob_other, :float)
    field(:llama_time_seconds, :float)
    field(:classification_count, :integer, default: 0)

    has_many(:classifications, TweetClassification, foreign_key: :disagreement_tweet_id)

    timestamps()
  end

  @required_fields [:tweet_id, :timestamp, :screen_name, :text, :url, :agreement]
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
    :classification_count
  ]

  def changeset(disagreement_tweet, attrs) do
    disagreement_tweet
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:tweet_id)
    |> validate_inclusion(:agreement, [true, false])
    |> validate_number(:classification_count, greater_than_or_equal_to: 0)
  end

  def with_classification_count(query \\ __MODULE__) do
    from(dt in query,
      left_join: tc in assoc(dt, :classifications),
      group_by: dt.id,
      select_merge: %{classification_count: count(tc.id)}
    )
  end

  def by_classification_count(query \\ __MODULE__, count) do
    from(dt in query, where: dt.classification_count == ^count)
  end

  def not_classified_by_user(query \\ __MODULE__, user_id) do
    from(dt in query,
      left_join: tc in assoc(dt, :classifications),
      on: tc.user_id == ^user_id,
      where: is_nil(tc.id)
    )
  end

  def classified_by_user(query \\ __MODULE__, user_id) do
    from(dt in query,
      join: tc in assoc(dt, :classifications),
      where: tc.user_id == ^user_id
    )
  end

  def in_prob_range(query \\ __MODULE__, min_prob, max_prob) do
    from(dt in query,
      where:
        (dt.openai_prob_true >= ^min_prob and dt.openai_prob_true <= ^max_prob) or
          (dt.llama_prob_true >= ^min_prob and dt.llama_prob_true <= ^max_prob)
    )
  end

  def order_by_timestamp(query \\ __MODULE__, direction \\ :desc) do
    from(dt in query, order_by: [{^direction, dt.timestamp}])
  end
end
