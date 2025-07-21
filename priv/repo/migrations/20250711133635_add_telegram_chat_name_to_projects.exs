defmodule Sanbase.Repo.Migrations.AddTelegramChatNameToProjects do
  use Ecto.Migration

  def change do
    alter table(:project) do
      add(:telegram_chat_name, :string)
    end
  end
end
