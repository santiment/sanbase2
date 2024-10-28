defmodule Sanbase.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def up do
    NotificationStepEnum.create_type()
    NotificationChannelEnum.create_type()

    create table(:notifications) do
      add(:step, NotificationStepEnum.type(), null: false)
      add(:status, NotificationStatusEnum.type(), default: "pending", null: false)
      add(:scheduled_at, :utc_datetime, null: false)
      add(:sent_at, :utc_datetime)
      add(:channels, {:array, NotificationChannelEnum.type()}, null: false)
      add(:content, :text)
      add(:display_in_ui, :boolean, default: false, null: false)
      add(:template_params, :map, null: false)

      add(:notification_action_id, references(:notification_actions, on_delete: :delete_all),
        null: false
      )

      timestamps()
    end

    create(index(:notifications, [:notification_action_id]))
  end

  def down do
    drop(table(:notifications))

    NotificationStepEnum.drop_type()
    NotificationChannelEnum.drop_type()
  end
end
