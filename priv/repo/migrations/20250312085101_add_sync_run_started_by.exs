defmodule Sanbase.Repo.Migrations.AddSyncRunStartedBy do
  use Ecto.Migration

  def change do
    alter table(:metric_registry_sync_runs) do
      add(:started_by, :string)
    end
  end
end
