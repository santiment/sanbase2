defmodule Sanbase.Repo.Migrations.AddTimelineEventsTable do
  use Ecto.Migration

  @table :timeline_events
  def change do
    create table(@table) do
      add(:event_type, :string)
      add(:user_id, references(:users))
      add(:post_id, references(:posts))
      add(:user_list_id, references(:user_lists))
      add(:user_trigger_id, references(:user_triggers))
      timestamps(updated_at: false)
    end

    fk_check = """
    (CASE WHEN post_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN user_list_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN user_trigger_id IS NULL THEN 0 ELSE 1 END) = 1
    """

    create(constraint(@table, :only_one_fk, check: fk_check))
    create(index(@table, [:user_id, :inserted_at]))
  end
end
