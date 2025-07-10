defmodule Sanbase.Repo.Migrations.AddFeedbackTypeToChatMessages do
  use Ecto.Migration

  def change do
    alter table(:chat_messages) do
      add(:feedback_type, :string, null: true)
    end

    create(
      constraint(:chat_messages, :valid_feedback_type,
        check: "feedback_type IN ('thumbs_up', 'thumbs_down') OR feedback_type IS NULL"
      )
    )
  end
end
