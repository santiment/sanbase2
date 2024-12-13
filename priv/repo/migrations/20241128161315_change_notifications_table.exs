defmodule Sanbase.Repo.Migrations.ChangeNotificationsTable do
  use Ecto.Migration

  def up do
    alter table(:notifications) do
      # Remove old fields
      remove(:channels)
      remove(:processed_for_discord)
      remove(:processed_for_discord_at)
      remove(:processed_for_email)
      remove(:processed_for_email_at)

      # Add new fields
      add(:channel, :string, null: false)
      add(:status, :string, null: false, default: "available")
      add(:job_id, :bigint)
      add(:is_manual, :boolean, null: false, default: false)
      add(:metric_registry_id, references(:metric_registry))
      add(:notification_template_id, references(:notification_templates))
      add(:scheduled_at, :utc_datetime)
    end

    create(index(:notifications, [:job_id]))
    create(index(:notifications, [:metric_registry_id]))
    create(index(:notifications, [:notification_template_id]))
    create(index(:notifications, [:status]))
  end

  def down do
    drop(index(:notifications, [:status]))
    drop(index(:notifications, [:notification_template_id]))
    drop(index(:notifications, [:metric_registry_id]))
    drop(index(:notifications, [:job_id]))

    alter table(:notifications) do
      # Restore old fields
      add(:channels, :string)
      add(:processed_for_discord, :boolean)
      add(:processed_for_discord_at, :utc_datetime)
      add(:processed_for_email, :boolean)
      add(:processed_for_email_at, :utc_datetime)

      # Remove new fields
      remove(:channel)
      remove(:status)
      remove(:job_id)
      remove(:is_manual)
      remove(:metric_registry_id)
      remove(:notification_template_id)
      remove(:scheduled_at)
    end
  end
end
