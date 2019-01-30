defmodule Sanbase.Repo.Migrations.CreateUserTriggersTable do
  use Ecto.Migration

  def change do
    create table("user_triggers") do
      add(:user_id, references("users"), null: false)
      add(:trigger, :jsonb, null: false)

      timestamps()
    end

    create(index("user_triggers", [:user_id]))
  end
end
