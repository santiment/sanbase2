defmodule Sanbase.Repo.Migrations.AddQueryVotes do
  @moduledoc false
  use Ecto.Migration

  @table :votes
  def up do
    alter table(@table) do
      add(:query_id, references(:queries), null: true)
    end

    fk_check = """
    CASE WHEN post_id IS NULL THEN 0 ELSE 1 END +
    CASE WHEN timeline_event_id IS NULL THEN 0 ELSE 1 END +
    CASE WHEN chart_configuration_id IS NULL THEN 0 ELSE 1 END +
    CASE WHEN watchlist_id IS NULL THEN 0 ELSE 1 END +
    CASE WHEN user_trigger_id IS NULL THEN 0 ELSE 1 END +
    CASE WHEN dashboard_id IS NULL THEN 0 ELSE 1 END +
    CASE WHEN query_id IS NULL THEN 0 ELSE 1 END = 1
    """

    drop(constraint(@table, "only_one_fk"))
    create(constraint(@table, :only_one_fk, check: fk_check))

    create(unique_index(@table, [:query_id, :user_id]))
  end

  def down do
    fk_check = """
    CASE WHEN post_id IS NULL THEN 0 ELSE 1 END +
    CASE WHEN timeline_event_id IS NULL THEN 0 ELSE 1 END +
    CASE WHEN chart_configuration_id IS NULL THEN 0 ELSE 1 END +
    CASE WHEN watchlist_id IS NULL THEN 0 ELSE 1 END +
    CASE WHEN user_trigger_id IS NULL THEN 0 ELSE 1 END +
    CASE WHEN dashboard_id IS NULL THEN 0 ELSE 1 END = 1
    """

    drop(constraint(@table, "only_one_fk"))

    create(constraint(@table, :only_one_fk, check: fk_check))

    drop(unique_index(@table, [:query_id, :user_id]))

    alter table(@table) do
      remove(:query_id)
    end
  end
end
