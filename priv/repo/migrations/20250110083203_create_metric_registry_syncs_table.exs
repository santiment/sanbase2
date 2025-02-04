defmodule Sanbase.Repo.Migrations.CreateMetricRegistrySyncsTable do
  use Ecto.Migration

  def change do
    create table(:metric_registry_sync_runs) do
      add(:uuid, :string)
      # incoming on prod, outgoing on stage
      add(:sync_type, :string)
      add(:status, :string)
      add(:content, :text)
      add(:actual_changes, :text)
      add(:errors, :text)

      timestamps()
    end

    create(unique_index(:metric_registry_sync_runs, [:uuid, :sync_type]))
  end
end
