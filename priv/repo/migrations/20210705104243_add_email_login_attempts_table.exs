defmodule Sanbase.Repo.Migrations.AddEmailLoginAttemptsTable do
  use Ecto.Migration

  def change do
    create table(:email_login_attempts) do
      add(:user_id, references(:users), on_delete: :delete_all, null: false)

      timestamps()
    end
  end
end
