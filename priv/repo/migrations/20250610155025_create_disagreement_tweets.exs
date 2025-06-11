defmodule Sanbase.Repo.Migrations.CreateDisagreementTweets do
  use Ecto.Migration

  def change do
    create table(:disagreement_tweets) do
      add(:tweet_id, :string, null: false)
      add(:timestamp, :utc_datetime, null: false)
      add(:screen_name, :string, null: false)
      add(:text, :text, null: false)
      add(:url, :string, null: false)
      add(:agreement, :boolean, null: false, default: false)
      add(:openai_is_prediction, :boolean)
      add(:openai_prob_true, :float)
      add(:openai_prob_false, :float)
      add(:openai_prob_other, :float)
      add(:openai_time_seconds, :float)
      add(:llama_is_prediction, :boolean)
      add(:llama_prob_true, :float)
      add(:llama_prob_false, :float)
      add(:llama_prob_other, :float)
      add(:llama_time_seconds, :float)
      add(:classification_count, :integer, default: 0)

      timestamps()
    end

    create table(:tweet_classifications) do
      add(:disagreement_tweet_id, references(:disagreement_tweets, on_delete: :delete_all),
        null: false
      )

      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:is_prediction, :boolean, null: false)
      add(:classified_at, :utc_datetime, null: false)

      timestamps()
    end

    create(unique_index(:disagreement_tweets, [:tweet_id]))
    create(unique_index(:tweet_classifications, [:disagreement_tweet_id, :user_id]))
    create(index(:tweet_classifications, [:user_id]))
    create(index(:disagreement_tweets, [:classification_count]))
    create(index(:disagreement_tweets, [:timestamp]))
  end
end
