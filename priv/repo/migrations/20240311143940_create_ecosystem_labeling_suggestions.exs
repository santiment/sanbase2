defmodule Sanbase.Repo.Migrations.CreateEcosystemLabelingSuggestions do
  use Ecto.Migration

  def change do
    create table(:project_ecosystem_labels_change_suggestions) do
      add(:project_id, references(:project, on_delete: :delete_all))
      add(:added_ecosystems, {:array, :string})
      add(:removed_ecosystems, {:array, :string})
      add(:notes, :text)

      add(:status, :string, default: "pending_approval")

      timestamps()
    end
  end
end
