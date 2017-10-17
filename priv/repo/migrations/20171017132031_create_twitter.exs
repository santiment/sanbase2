defmodule Sanbase.Repo.Migrations.CreateTwitter do
  use Ecto.Migration

  def change do
    create table(:twitter) do
      add :project_id, references(:project, type: :serial, on_delete: :nothing), null: false
      add :link, :text
      add :joindate, :date
      add :tweets, :integer
      add :followers, :integer
      add :following, :integer
      add :likes, :integer
    end
    create unique_index(:twitter, [:project_id])

  end
end
