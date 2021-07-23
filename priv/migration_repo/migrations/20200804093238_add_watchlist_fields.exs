defmodule Sanbase.Repo.Migrations.AddWatchlistFields do
  use Ecto.Migration

  def change do
    alter table(:user_lists) do
      add(:description, :text)
    end
  end
end
