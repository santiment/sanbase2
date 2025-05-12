defmodule Sanbase.Repo.Migrations.CreateScheduledDeprecationNotifications do
  use Ecto.Migration

  def change do
    create table(:scheduled_deprecation_notifications) do
      add(:deprecation_date, :date, null: false)
      add(:contact_list_name, :string, null: false)
      add(:api_endpoint, :string, null: false)
      add(:links, {:array, :string}, null: false)

      # Initial Schedule Email
      add(:schedule_email_subject, :string, null: false)
      add(:schedule_email_html, :text, null: false)
      add(:schedule_email_scheduled_at, :utc_datetime, null: false)
      add(:schedule_email_job_id, :string)
      add(:schedule_email_sent_at, :utc_datetime)
      add(:schedule_email_dispatch_status, :string, default: "pending", null: false)

      # Reminder Email
      add(:reminder_email_subject, :string, null: false)
      add(:reminder_email_html, :text, null: false)
      add(:reminder_email_scheduled_at, :utc_datetime, null: false)
      add(:reminder_email_job_id, :string)
      add(:reminder_email_sent_at, :utc_datetime)
      add(:reminder_email_dispatch_status, :string, default: "pending", null: false)

      # Executed Email (on deprecation day)
      add(:executed_email_subject, :string, null: false)
      add(:executed_email_html, :text, null: false)
      add(:executed_email_scheduled_at, :utc_datetime, null: false)
      add(:executed_email_job_id, :string)
      add(:executed_email_sent_at, :utc_datetime)
      add(:executed_email_dispatch_status, :string, default: "pending", null: false)

      add(:status, :string, null: false, default: "pending")

      timestamps()
    end

    create(index(:scheduled_deprecation_notifications, [:status]))
    create(index(:scheduled_deprecation_notifications, [:deprecation_date]))
  end
end
