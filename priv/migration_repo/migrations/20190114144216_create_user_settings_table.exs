defmodule Sanbase.Repo.Migrations.CreateUserSettingsTable do
  use Ecto.Migration

  def change do
    create table("user_settings") do
      add(:user_id, references("users"), null: false)
      add(:settings, :jsonb)

      timestamps()
    end

    create(index("user_settings", [:user_id]))
  end
end
