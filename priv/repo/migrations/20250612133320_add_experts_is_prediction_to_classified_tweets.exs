defmodule Sanbase.Repo.Migrations.AddExpertsIsPredictionToClassifiedTweets do
  use Ecto.Migration

  def change do
    alter table(:classified_tweets) do
      add(:experts_is_prediction, :boolean, null: true)
    end

    create(index(:classified_tweets, [:experts_is_prediction]))
  end
end
