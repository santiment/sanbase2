defmodule Sanbase.Repo.Migrations.ChangeVotesDashboardIndex do
  use Ecto.Migration

  def change do
    drop(index(:votes, [:dashboard_id], name: :votes_dashboard_id_index))

    create(index(:votes, [:dashboard_id, :user_id]))
  end
end
