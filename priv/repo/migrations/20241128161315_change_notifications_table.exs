defmodule Sanbase.Repo.Migrations.ChangeNotificationsTable do
  use Ecto.Migration

  def change do
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
    end

    create(index(:notifications, [:job_id]))
    create(index(:notifications, [:metric_registry_id]))
    create(index(:notifications, [:notification_template_id]))
    create(index(:notifications, [:status]))
  end
end
