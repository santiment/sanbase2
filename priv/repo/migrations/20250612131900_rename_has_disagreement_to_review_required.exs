defmodule Sanbase.Repo.Migrations.RenameHasDisagreementToReviewRequired do
  use Ecto.Migration

  def up do
    # Drop the existing index
    drop(index(:classified_tweets, [:has_disagreement]))

    # Rename the column
    rename(table(:classified_tweets), :has_disagreement, to: :review_required)

    # Create new index
    create(index(:classified_tweets, [:review_required]))
  end

  def down do
    # Drop the new index
    drop(index(:classified_tweets, [:review_required]))

    # Rename the column back
    rename(table(:classified_tweets), :review_required, to: :has_disagreement)

    # Create the original index
    create(index(:classified_tweets, [:has_disagreement]))
  end
end
