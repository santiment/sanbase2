defmodule Sanbase.Repo.Migrations.AddAssetDirectionToClassifiedTweets do
  use Ecto.Migration

  def change do
    alter table(:classified_tweets) do
      add(:prediction_direction, :string, null: true)
      add(:base_asset, :string, null: true)
      add(:quote_asset, :string, null: true)
    end

    create(index(:classified_tweets, [:prediction_direction]))
    create(index(:classified_tweets, [:base_asset]))
    create(index(:classified_tweets, [:quote_asset]))
  end
end
