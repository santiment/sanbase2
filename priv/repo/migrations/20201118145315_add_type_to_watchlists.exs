defmodule Sanbase.Repo.Migrations.AddTypeToWatchlists do
  use Ecto.Migration

  def change do
    WatchlistType.create_type()

    alter table(:user_lists) do
      add(:type, :watchlist_type, null: false, default: "project")
    end
  end
end
