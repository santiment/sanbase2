defmodule Sanbase.Repo.Migrations.AddEmailLoginAttemptsTable do
  use Ecto.Migration

  def change do
    create table(:email_login_attempts) do
      add(:user_id, references(:users), on_delete: :delete_all, null: false)
      add(:ip_address, :string, size: 15)

      index(:email_login_attempts, [:user_id])
      index(:email_login_attempts, [:ip_address])

      timestamps()
    end
  end
end
