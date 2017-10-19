defmodule Sanbase.Repo.Migrations.CreateFacebook do
  use Ecto.Migration

  def change do
    create table(:facebook) do
      add :project_id, references(:project, on_delete: :delete_all), null: false
      add :link, :text
      add :likes, :integer
    end
    create unique_index(:facebook, [:project_id])
  end
end
