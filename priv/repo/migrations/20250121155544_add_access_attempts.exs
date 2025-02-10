defmodule Sanbase.Repo.Migrations.AddAccessAttempts do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:access_attempts) do
      add(:user_id, references(:users), null: true)
      add(:ip_address, :string, null: false)
      add(:type, :string, null: false)

      timestamps()
    end

    create(index(:access_attempts, [:type, :ip_address, :inserted_at]))
    create(index(:access_attempts, [:type, :user_id, :inserted_at]))
  end
end
