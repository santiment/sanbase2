defmodule Sanbase.Repo.Migrations.CreateTwitter do
  use Ecto.Migration

  def change do
    create table(:twitter) do
      add :project_id, references(:project, on_delete: :delete_all), null: false
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
