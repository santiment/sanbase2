defmodule Sanbase.Repo.Migrations.AddTelegramIdToProjects do
  use Ecto.Migration

  def change do
    alter table(:project) do
      add(:telegram_chat_id, :integer)
    end
  end
end
