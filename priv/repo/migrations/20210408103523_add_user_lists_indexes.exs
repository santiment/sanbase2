defmodule Sanbase.Repo.Migrations.AddUserListsIndexes do
  use Ecto.Migration

  def change do
    create(index(:timeline_events, [:user_id]))
    create(index(:watchlist_settings, [:user_id]))
  end
end
