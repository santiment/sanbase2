defmodule Sanbase.Repo.Migrations.AddTelegramChatIdToProjects do
  use Ecto.Migration

  def change do
    alter table(:project) do
      add(:telegram_chat_id, :integer, null: true)
    end
  end
end
