defmodule Sanbase.Repo.Migrations.DropNotificationsTables do
  @moduledoc false
  use Ecto.Migration

  def up do
    drop(table(:notifications))
    drop(table(:notification))
    drop(table(:notification_type))
  end

  def down do
    create table(:notification_type) do
      add(:name, :string, null: false)
      timestamps()
    end

    create table(:notifications) do
      add(:project_id, references(:project), null: false)
      add(:type_id, references(:notification_type), null: false)
      add(:data, :string)

      timestamps()
    end

    create(index(:notifications, [:project_id, :type_id]))

    create(unique_index(:notification_type, [:name]))

    create table(:notification) do
      add(:project_id, references(:project), null: false)
      add(:type_id, references(:notification_type), null: false)
      timestamps()
    end

    create(index(:notification, [:project_id, :type_id]))
  end
end
