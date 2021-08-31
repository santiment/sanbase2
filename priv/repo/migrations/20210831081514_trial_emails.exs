defmodule Sanbase.Repo.Migrations.TrialEmails do
  use Ecto.Migration

  def change do
    create table(:trial_emails) do
      add(:user_id, references(:users, on_delete: :delete_all))
      add(:subscription_id, references(:subscriptions, on_delete: :delete_all))
      add(:sent_welcome_email, :boolean, dafault: false)
      add(:sent_first_education_email, :boolean, dafault: false)
      add(:sent_second_education_email, :boolean, dafault: false)
      add(:is_finished, :boolean, default: false)

      timestamps()
    end

    create(unique_index(:trial_emails, [:user_id]))
    create(unique_index(:trial_emails, [:subscription_id]))
  end
end
