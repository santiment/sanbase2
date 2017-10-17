defmodule Sanbase.Repo.Migrations.CreateReddit do
  use Ecto.Migration

  def change do
    create table(:reddit) do
      add :project_id, references(:project, type: :serial, on_delete: :nothing), null: false
      add :link, :text
      add :subscribers, :integer
    end
    create unique_index(:reddit, [:project_id])

  end
end
