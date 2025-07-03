defmodule Sanbase.Repo.Migrations.SimpleRenameToClassifiedTweets do
  use Ecto.Migration

  def up do
    # Rename the table
    rename(table(:disagreement_tweets), to: table(:classified_tweets))

    # Add disagreement flag - default to true for existing records
    alter table(:classified_tweets) do
      add(:has_disagreement, :boolean, default: true, null: false)
    end

    # Rename foreign key column
    rename(table(:tweet_classifications), :disagreement_tweet_id, to: :classified_tweet_id)

    # Add index for has_disagreement
    create(index(:classified_tweets, [:has_disagreement]))
  end

  def down do
    # Remove disagreement flag
    alter table(:classified_tweets) do
      remove(:has_disagreement)
    end

    # Revert table name
    rename(table(:classified_tweets), to: table(:disagreement_tweets))

    # Revert foreign key column
    rename(table(:tweet_classifications), :classified_tweet_id, to: :disagreement_tweet_id)

    # Drop has_disagreement index
    drop(index(:classified_tweets, [:has_disagreement]))
  end
end
