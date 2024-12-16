defmodule Sanbase.Repo.Migrations.CreateMetricRegistrySyncsTable do
  use Ecto.Migration

  def change do
    create table(:metric_registry_syncs) do
      add(:uuid, :string)
      add(:status, :string)
      add(:content, :text)
      add(:errors, :text)

      timestamps()
    end

    create(unique_index(:metric_registry_syncs, [:uuid]))
  end
end
