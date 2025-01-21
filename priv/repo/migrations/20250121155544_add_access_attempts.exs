defmodule Sanbase.Repo.Migrations.AddAccessAttempts do
  use Ecto.Migration

  def change do
    create table(:access_attempts) do
      add(:user_id, references(:users), null: true)
      add(:ip_address, :string, null: false)
      add(:type, :string, null: false)

      timestamps()
    end

    create(index(:access_attempts, [:user_id]))
    create(index(:access_attempts, [:ip_address]))
    create(index(:access_attempts, [:type]))
    create(index(:access_attempts, [:inserted_at]))
  end
end
