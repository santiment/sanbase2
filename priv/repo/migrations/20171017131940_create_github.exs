defmodule Sanbase.Repo.Migrations.CreateGithub do
  use Ecto.Migration

  def change do
    create table(:github) do
      add :project_id, references(:project, type: :serial, on_delete: :nothing), null: false
      add :link, :text
      add :commits, :integer
      add :contributors, :integer
    end

    create unique_index(:github, [:project_id])
  end
end
