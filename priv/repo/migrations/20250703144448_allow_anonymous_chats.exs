defmodule Sanbase.Repo.Migrations.AllowAnonymousChats do
  use Ecto.Migration

  def up do
    # Allow anonymous chats by making user_id nullable
    alter table(:chats) do
      modify(:user_id, :integer, null: true)
    end

    # Add index for cleanup operations (anonymous chats older than X days)
    create(index(:chats, [:user_id, :updated_at], name: :chats_user_id_updated_at_index))

    # Add index for anonymous chats specifically
    create(
      index(:chats, [:updated_at],
        where: "user_id IS NULL",
        name: :chats_anonymous_updated_at_index
      )
    )
  end

  def down do
    # Remove indexes
    drop(index(:chats, [:user_id, :updated_at], name: :chats_user_id_updated_at_index))

    drop(
      index(:chats, [:updated_at],
        where: "user_id IS NULL",
        name: :chats_anonymous_updated_at_index
      )
    )

    # Note: We can't easily revert user_id to NOT NULL without data loss
    # This would require deleting all anonymous chats first
    # For safety, we'll leave it nullable in rollback
  end
end
