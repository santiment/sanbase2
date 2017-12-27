defmodule Sanbase.Repo.Migrations.CreateProjectTransparencyStatusFk do
  use Ecto.Migration

  def change do
    alter table(:project) do
      remove :project_transparency_status
      add :project_transparency_status_id, references(:project_transparency_statuses)
    end

    create index(:project, [:project_transparency_status_id])
  end
end
