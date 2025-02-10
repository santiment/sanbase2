defmodule Sanbase.Repo.Migrations.AddTimelineEventsFKToVotes do
  @moduledoc false
  use Ecto.Migration

  @table :votes

  def up do
    drop(constraint(@table, "votes_post_id_fkey"))

    alter table(@table) do
      modify(:post_id, references(:posts, on_delete: :delete_all), null: true)
      add(:timeline_event_id, references(:timeline_events, on_delete: :delete_all), null: true)
    end

    fk_check = """
    (CASE WHEN post_id IS NULL THEN 0 ELSE 1 END) + (CASE WHEN timeline_event_id IS NULL THEN 0 ELSE 1 END) = 1
    """

    create(constraint(@table, :only_one_fk, check: fk_check))
    create(unique_index(@table, [:timeline_event_id, :user_id]))
  end

  def down do
    drop(constraint(@table, "only_one_fk"))
    drop(constraint(@table, "votes_post_id_fkey"))

    alter table(@table) do
      remove(:timeline_event_id)
      modify(:post_id, references(:posts, on_delete: :delete_all), null: false)
    end
  end
end
