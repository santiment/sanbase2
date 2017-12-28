defmodule Sanbase.Repo.Migrations.AddNotificationProjectFkCascadeDelete do
  use Ecto.Migration

  def up do
    drop constraint(:notification, "notification_project_id_fkey")
    alter table(:notification) do
      modify :project_id, references(:project, on_delete: :delete_all), null: false
    end
  end

  def down do
    drop constraint(:notification, "notification_project_id_fkey")
    alter table(:notification) do
      modify :project_id, references(:project, on_delete: :nothing), null: false
    end
  end
end
