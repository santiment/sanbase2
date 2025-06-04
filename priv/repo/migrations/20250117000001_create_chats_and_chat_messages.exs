defmodule Sanbase.Repo.Migrations.CreateChatsAndChatMessages do
  use Ecto.Migration

  def change do
    create table(:chats, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:title, :string, null: false)
      add(:user_id, references(:users, on_delete: :delete_all), null: false)

      timestamps()
    end

    create(index(:chats, [:user_id]))
    create(index(:chats, [:inserted_at]))

    create table(:chat_messages, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:chat_id, references(:chats, type: :binary_id, on_delete: :delete_all), null: false)
      add(:content, :text, null: false)
      add(:role, :string, null: false)
      add(:context, :map, default: %{})

      timestamps()
    end

    create(index(:chat_messages, [:chat_id]))
    create(index(:chat_messages, [:inserted_at]))
    create(index(:chat_messages, [:role]))

    create(constraint(:chat_messages, :valid_role, check: "role IN ('user', 'assistant')"))
  end
end
