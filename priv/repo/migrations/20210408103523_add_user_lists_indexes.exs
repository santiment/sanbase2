defmodule Sanbase.Repo.Migrations.AddUserListsIndexes do
  use Ecto.Migration

  def change do
    create(index(:timeline_events, [:user_list_id]))
    create(index(:watchlist_settings, [:watchlist_id]))
  end
end
