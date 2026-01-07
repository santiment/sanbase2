defmodule Sanbase.Repo.Migrations.AddWatchlistIsPublicUpdatedAtTimestamp do
  use Ecto.Migration

  def change do
    alter table(:user_lists) do
      add(:is_public_updated_at, :utc_datetime)
    end
  end
end
