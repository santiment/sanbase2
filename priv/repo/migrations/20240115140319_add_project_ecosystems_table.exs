defmodule Sanbase.Repo.Migrations.AddProjectEcosystemsTable do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:ecosystems) do
      add(:ecosystem, :string, null: false)

      timestamps()
    end

    create(unique_index(:ecosystems, [:ecosystem]))

    create table(:project_ecosystem_mappings) do
      add(:project_id, references(:project, on_delete: :nothing), null: false)
      add(:ecosystem_id, references(:ecosystems, on_delete: :nothing), null: false)
      timestamps()
    end

    create(unique_index(:project_ecosystem_mappings, [:project_id, :ecosystem_id]))
  end
end
