defmodule Sanbase.Repo.Migrations.DropPostsProjectsTable do
  use Ecto.Migration

  def change do
    drop(table(:posts_projects))
  end
end
