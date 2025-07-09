defmodule Sanbase.Repo.Migrations.AddSuggestionsToChatMessages do
  use Ecto.Migration

  def change do
    alter table(:chat_messages) do
      add(:suggestions, {:array, :string}, default: [])
    end
  end
end
