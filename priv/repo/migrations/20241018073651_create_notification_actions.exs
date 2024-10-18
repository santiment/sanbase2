defmodule Sanbase.Repo.Migrations.CreateNotificationActions do
  use Ecto.Migration

  def up do
    NotificationActionTypeEnum.create_type()
    NotificationStatusEnum.create_type()

    create table(:notification_actions) do
      add(:action_type, NotificationActionTypeEnum.type(), null: false)
      add(:scheduled_at, :utc_datetime, null: false)
      add(:status, NotificationStatusEnum.type(), default: "pending", null: false)
      add(:requires_verification, :boolean, default: false, null: false)
      add(:verified, :boolean, default: false, null: false)

      timestamps()
    end
  end

  def down do
    drop(table(:notification_actions))

    NotificationActionTypeEnum.drop_type()
    NotificationStatusEnum.drop_type()
  end
end
