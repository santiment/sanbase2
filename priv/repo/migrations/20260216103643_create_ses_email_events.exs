defmodule Sanbase.Repo.Migrations.CreateSesEmailEvents do
  use Ecto.Migration

  def change do
    create table(:ses_email_events) do
      add(:message_id, :string, null: false)
      add(:email, :string, null: false)
      add(:event_type, :string, null: false)
      add(:bounce_type, :string)
      add(:bounce_sub_type, :string)
      add(:complaint_feedback_type, :string)
      add(:reject_reason, :string)
      add(:delay_type, :string)
      add(:smtp_response, :string)
      add(:timestamp, :utc_datetime, null: false)
      add(:raw_data, :map)

      timestamps()
    end

    create(index(:ses_email_events, [:email]))
    create(index(:ses_email_events, [:event_type]))
    create(index(:ses_email_events, [:message_id]))
    create(index(:ses_email_events, [:inserted_at]))
    create(unique_index(:ses_email_events, [:message_id, :email, :event_type]))
  end
end
