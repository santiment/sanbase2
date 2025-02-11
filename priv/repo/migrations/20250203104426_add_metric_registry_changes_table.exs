defmodule Sanbase.Repo.Migrations.AddMetricRegistryChangesTable do
  use Ecto.Migration

  def change do
    create table(:metric_registry_changelog) do
      add(:metric_registry_id, references(:metric_registry))
      add(:old, :text)
      add(:new, :text)

      timestamps()
    end

    create(index(:metric_registry_changelog, [:metric_registry_id]))
  end
end
