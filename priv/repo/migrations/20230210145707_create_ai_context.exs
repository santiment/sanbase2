defmodule Sanbase.Repo.Migrations.CreateAiContext do
  use Ecto.Migration

  def change do
    create table(:ai_context) do
      add(:discord_user, :string)
      add(:question, :text)
      add(:answer, :text)

      timestamps()
    end
  end
end
