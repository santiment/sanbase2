defmodule Sanbase.Repo.Migrations.AddEmailLoginAttemptsTable do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:email_login_attempts) do
      add(:user_id, references(:users), on_delete: :delete_all, null: false)
      add(:ip_address, :string, size: 15)

      timestamps()
    end

    create(index(:email_login_attempts, [:user_id]))
    create(index(:email_login_attempts, [:ip_address]))
  end
end
