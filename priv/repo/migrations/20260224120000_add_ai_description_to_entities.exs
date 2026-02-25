defmodule Sanbase.Repo.Migrations.AddAiDescriptionToEntities do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add(:ai_description, :text)
    end

    alter table(:chart_configurations) do
      add(:ai_description, :text)
    end

    alter table(:user_lists) do
      add(:ai_description, :text)
    end
  end
end
