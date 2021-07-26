defmodule Sanbase.Repo.Migrations.AddUserTriggersTagsTable do
  use Ecto.Migration

  def change do
    create table(:user_triggers_tags) do
      add(:user_trigger_id, references(:user_triggers))
      add(:tag_id, references(:tags))
    end

    create(unique_index(:user_triggers_tags, [:user_trigger_id, :tag_id]))
  end
end
