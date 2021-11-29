defmodule Sanbase.Repo.Migrations.AddWatchlistVotes do
  use Ecto.Migration

  @table :votes
  def up do
    alter table(@table) do
      add(:watchlist_id, references(:user_lists), null: true)
    end

    fk_check = """
    (CASE WHEN post_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN timeline_event_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN chart_configuration_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN watchlist_id IS NULL THEN 0 ELSE 1 END) = 1
    """

    drop(constraint(@table, "only_one_fk"))
    create(constraint(@table, :only_one_fk, check: fk_check))

    create(unique_index(@table, [:watchlist_id, :user_id]))
  end

  def down do
    fk_check = """
    (CASE WHEN post_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN timeline_event_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN chart_configuration_id IS NULL THEN 0 ELSE 1 END) = 1
    """

    drop(constraint(@table, "only_one_fk"))

    create(constraint(@table, :only_one_fk, check: fk_check))

    drop(unique_index(@table, [:watchlist_id, :user_id]))

    alter table(@table) do
      remove(:watchlist_id)
    end
  end
end
