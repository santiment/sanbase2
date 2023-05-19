defmodule Sanbase.Repo.Migrations.UpdateAiContext do
  use Ecto.Migration

  def change do
    alter table(:ai_context) do
      add(:prompt, :text)
      modify(:error_message, :text)
    end
  end
end
