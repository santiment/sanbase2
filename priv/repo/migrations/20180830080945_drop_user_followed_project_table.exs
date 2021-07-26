defmodule Sanbase.Repo.Migrations.DropUserFollowedProjectTable do
  use Ecto.Migration

  def change do
    drop(table(:user_followed_project))
  end
end
