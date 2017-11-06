defmodule Sanbase.Repo.Migrations.AddNotifications do
  use Ecto.Migration

  def change do
    create table("notification_type") do
      add :name, :string, null: false
      timestamps()
    end
    create unique_index("notification_type", [:name])

    create table("notification") do
      add :project_id, references("project"), null: false
      add :type_id, references("notification_type"), null: false
      timestamps()
    end
    create index("notification", [:project_id, :type_id])
  end
end
