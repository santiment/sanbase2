defmodule Sanbase.Repo.Migrations.CreateTelegramUserTokens do
  use Ecto.Migration

  @table "telegram_user_tokens"
  def change do
    create table(@table, primary_key: false) do
      add(:user_id, references(:users), null: false, primary_key: true)
      add(:token, :string, null: false, primary_key: true)
      timestamps()
    end

    create(unique_index(@table, [:token]))
    create(unique_index(@table, [:user_id]))
  end
end
