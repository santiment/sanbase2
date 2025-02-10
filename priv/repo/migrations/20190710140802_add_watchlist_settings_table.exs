defmodule Sanbase.Repo.Migrations.AddWatchlistSettingsTable do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:watchlist_settings, primary_key: false) do
      add(:user_id, references(:users, on_delete: :delete_all), primary_key: true)
      add(:watchlist_id, references(:user_lists, on_delete: :delete_all), primary_key: true)
      add(:settings, :jsonb)
    end
  end
end
