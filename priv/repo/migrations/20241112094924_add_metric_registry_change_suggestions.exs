defmodule Sanbase.Repo.Migrations.AddMetricRegistryChangeSuggestions do
  use Ecto.Migration

  def change do
    create table(:metric_registry_change_suggestions) do
      add(:metric_registry_id, references(:metric_registry), on_delete: :delete_all)
      add(:status, :string, null: false, default: "pending_approval")
      add(:changes, :text, null: false)
      add(:notes, :text)
      add(:submitted_by, :string)

      timestamps()
    end
  end
end
