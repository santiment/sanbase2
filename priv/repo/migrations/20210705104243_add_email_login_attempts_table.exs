defmodule Sanbase.Repo.Migrations.AddEmailLoginAttemptsTable do
  use Ecto.Migration

  def change do
    create table(:email_login_attempts) do
      add(:user_id, references(:users), on_delete: :delete_all, null: false)
      add(:ip_address, :string, size: 15)

      timestamps()
    end
  end
end
