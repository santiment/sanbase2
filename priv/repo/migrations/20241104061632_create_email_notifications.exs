defmodule Sanbase.Repo.Migrations.CreateEmailNotifications do
  use Ecto.Migration

  def change do
    create table(:email_notifications) do
      add(:notification_id, references(:notifications, on_delete: :nilify_all))
      add(:to_addresses, {:array, :string}, null: false)
      add(:subject, :string, null: false)
      add(:content, :text, null: false)
      add(:status, :string, default: "pending")
      add(:approved_at, :utc_datetime)
      add(:sent_at, :utc_datetime)

      timestamps()
    end

    create(index(:email_notifications, [:notification_id]))
    create(index(:email_notifications, [:status]))
  end
end
