defmodule Sanbase.Repo.Migrations.AddDashboardVotes do
  use Ecto.Migration

  @table :votes
  def up do
    alter table(@table) do
      add(:dashboard_id, references(:dashboards), null: true)
    end

    fk_check = """
    (CASE WHEN post_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN timeline_event_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN chart_configuration_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN watchlist_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN user_trigger_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN dashboard_id IS NULL THEN 0 ELSE 1 END) = 1
    """

    drop(constraint(@table, "only_one_fk"))

    create(constraint(@table, :only_one_fk, check: fk_check))
    create(unique_index(@table, [:dashboard_id]))
  end

  def down do
    alter table(@table) do
      drop(:dashboard_id)
    end

    fk_check = """
    (CASE WHEN post_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN timeline_event_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN chart_configuration_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN watchlist_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN user_trigger_id IS NULL THEN 0 ELSE 1 END) = 1
    """

    # Dropping the column automatically dropped the constraint and the unique index
    create(constraint(@table, :only_one_fk, check: fk_check))
  end
end
