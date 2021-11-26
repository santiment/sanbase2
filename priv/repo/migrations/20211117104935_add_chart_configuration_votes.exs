defmodule Sanbase.Repo.Migrations.AddChartConfigurationVotes do
  use Ecto.Migration

  @table :votes
  def change do
    alter table(@table) do
      add(:chart_configuration_id, references(:chart_configurations), null: true)
    end

    fk_check = """
    (CASE WHEN post_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN timeline_event_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN chart_configuration_id IS NULL THEN 0 ELSE 1 END) = 1
    """

    drop(constraint(@table, "only_one_fk"))

    create(constraint(@table, :only_one_fk, check: fk_check))
    create(unique_index(@table, [:chart_configuration_id, :user_id]))
  end
end
