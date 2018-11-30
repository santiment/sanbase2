defmodule Sanbase.Repo.Migrations.AddNotificationsTable do
  use Ecto.Migration

  # There is currently `notification` table. To avoid dropping records from it
  # and also to conform to the standard that the table name is plural we'll create a new table,
  # start using it and drop the old one at some point
  def change do
    create table("notifications") do
      add(:project_id, references("project"), null: false)
      add(:type_id, references("notification_type"), null: false)
      add(:data, :string)

      timestamps()
    end

    create(index("notifications", [:project_id, :type_id]))
  end
end
