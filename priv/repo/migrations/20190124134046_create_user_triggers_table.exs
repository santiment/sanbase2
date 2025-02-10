defmodule Sanbase.Repo.Migrations.CreateUserTriggersTable do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table("user_triggers") do
      add(:user_id, references("users"), null: false)
      add(:trigger, :jsonb)

      timestamps()
    end

    create(index("user_triggers", [:user_id]))
  end
end
