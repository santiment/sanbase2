defmodule Sanbase.Repo.Migrations.AddVotesToUserTriggersTable do
  use Ecto.Migration

  @table :votes
  def change do
    alter table(@table) do
      add(:user_trigger_id, references(:user_triggers), null: true)
    end

    fk_check = """
    (CASE WHEN post_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN timeline_event_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN chart_configuration_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN watchlist_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN user_trigger_id IS NULL THEN 0 ELSE 1 END) = 1
    """

    drop(constraint(@table, "only_one_fk"))

    create(constraint(@table, :only_one_fk, check: fk_check))
    create(unique_index(@table, [:user_trigger_id, :user_id]))
  end
end
