defmodule Sanbase.Repo.Migrations.CreateTweetPredictions do
  use Ecto.Migration

  def change do
    create table(:tweet_predictions) do
      add(:tweet_id, :string, null: false)
      add(:timestamp, :utc_datetime, null: false)
      add(:text, :text, null: false)
      add(:url, :string, null: false)
      add(:is_prediction, :boolean, null: false)
      add(:is_interesting, :boolean, null: false, default: false)
      add(:screen_name, :string, null: false)

      timestamps()
    end

    create(unique_index(:tweet_predictions, [:tweet_id]))
  end
end
