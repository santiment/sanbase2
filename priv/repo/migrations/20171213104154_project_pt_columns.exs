defmodule Sanbase.Repo.Migrations.ProjectPtColumns do
  use Ecto.Migration

  def change do
    rename table(:project), :project_transparency, to: :project_transparency_status

    alter table(:project) do
      add :project_transparency, :boolean, null: false, default: false
      add :project_transparency_description, :text
    end
  end
end
