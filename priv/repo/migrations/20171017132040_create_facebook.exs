defmodule Sanbase.Repo.Migrations.CreateFacebook do
  use Ecto.Migration

  def change do
    create table(:facebook) do
      add :project_id, references(:project, type: :serial, on_delete: :nothing), null: false
      add :link, :text
      add :likes, :integer
    end
    create unique_index(:facebook, [:project_id])
  end
end
