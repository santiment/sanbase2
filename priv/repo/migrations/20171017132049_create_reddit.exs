defmodule Sanbase.Repo.Migrations.CreateReddit do
  use Ecto.Migration

  def change do
    create table(:reddit) do
      add :project_id, references(:project, on_delete: :delete_all), null: false
      add :link, :string
      add :subscribers, :integer
    end
    create unique_index(:reddit, [:project_id])

  end
end
