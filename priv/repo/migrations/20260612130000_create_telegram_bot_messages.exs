defmodule Sanbase.Repo.Migrations.CreateTelegramBotMessages do
  use Ecto.Migration

  def change do
    create table(:telegram_bot_messages) do
      add(:chat_id, :string, null: false)
      add(:message_id, :bigint, null: false)
      add(:conversation_id, :string, null: false)

      timestamps()
    end

    create(unique_index(:telegram_bot_messages, [:chat_id, :message_id]))
  end
end
