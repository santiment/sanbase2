defmodule Sanbase.Repo.Migrations.AddActualChangesToSyncs do
  use Ecto.Migration

  def change do
    alter table(:metric_registry_syncs) do
      add(:actual_changes, :text)
    end
  end
end
