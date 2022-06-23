defmodule Sanbase.Repo.Migrations.ModifyVotesConstraints do
  use Ecto.Migration

  @table :votes
  def up do
    drop(constraint(@table, "votes_watchlist_id_fkey"))
    drop(constraint(@table, "votes_user_trigger_id_fkey"))
    drop(constraint(@table, "votes_chart_configuration_id_fkey"))

    alter table(@table) do
      modify(:watchlist_id, references(:user_lists, on_delete: :delete_all))
      modify(:user_trigger_id, references(:user_triggers, on_delete: :delete_all))
      modify(:chart_configuration_id, references(:chart_configurations, on_delete: :delete_all))
    end
  end

  def down do
    drop(constraint(@table, "votes_watchlist_id_fkey"))
    drop(constraint(@table, "votes_user_trigger_id_fkey"))
    drop(constraint(@table, "votes_chart_configuration_id_fkey"))

    alter table(@table) do
      modify(:watchlist_id, references(:user_lists))
      modify(:user_trigger_id, references(:user_triggers))
      modify(:chart_configuration_id, references(:chart_configurations))
    end
  end
end
