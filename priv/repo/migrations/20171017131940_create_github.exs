defmodule Sanbase.Repo.Migrations.CreateGithub do
  use Ecto.Migration

  def change do
    create table(:github) do
      add :project_id, references(:project, on_delete: :delete_all), null: false
      add :link, :string
      add :commits, :integer
      add :contributors, :integer
    end

    create unique_index(:github, [:project_id])
  end
end
