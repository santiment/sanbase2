defmodule Sanbase.Repo.Migrations.AddUserFollowedProjectTable do
  use Ecto.Migration

  def change do
    create table(:user_followed_project) do
      add(:project_id, references(:project, on_delete: :delete_all), null: false)
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
    end

    create(
      unique_index(:user_followed_project, [:project_id, :user_id], name: :projet_user_constraint)
    )
  end
end
