defmodule Sanbase.Repo.Migrations.AddUserFollowedProjectTable do
  use Ecto.Migration


  def change do
    create table(:user_followed_project) do
      add :project_id, references(:project)
      add :user_id, references(:users)
    end

    create unique_index(:user_followed_project, [:project_id, :user_id], name: :projet_user_constraint)
  end
end
