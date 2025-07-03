defmodule Sanbase.DisagreementTweets.TweetClassification do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.DisagreementTweets.ClassifiedTweet
  alias Sanbase.Accounts.User

  schema "tweet_classifications" do
    field(:is_prediction, :boolean)
    field(:classified_at, :utc_datetime)

    belongs_to(:classified_tweet, ClassifiedTweet)
    belongs_to(:user, User)

    timestamps()
  end

  @required_fields [:classified_tweet_id, :user_id, :is_prediction, :classified_at]

  def changeset(classification, attrs) do
    classification
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:classified_tweet_id, :user_id])
    |> foreign_key_constraint(:classified_tweet_id)
    |> foreign_key_constraint(:user_id)
    |> validate_inclusion(:is_prediction, [true, false])
  end
end
