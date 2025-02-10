defmodule Sanbase.Repo.Migrations.CreateUserEvents do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:user_events) do
      add(:event_name, :string, null: false)
      add(:created_at, :utc_datetime, null: false)
      add(:metadata, :map)
      add(:remote_id, :string)
      add(:user_id, references(:users, on_delete: :nothing), null: false)

      timestamps()
    end

    create(index(:user_events, [:user_id]))
    create(unique_index(:user_events, [:remote_id]))
  end
end
