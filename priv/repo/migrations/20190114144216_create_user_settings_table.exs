defmodule Sanbase.Repo.Migrations.CreateUserSettingsTable do
  use Ecto.Migration

  def change do
    create table("user_settings") do
      add(:user_id, references("users"), null: false)
      add(:signal_notify_email, :boolean, default: false)
      add(:signal_notify_telegram, :boolean, default: false)
      add(:telegram_url, :string)

      timestamps()
    end

    create(index("user_settings", [:user_id]))
  end
end
