defmodule Sanbase.Repo.Migrations.FixDashboardVotesUniqueIndex do
  @moduledoc false
  use Ecto.Migration

  def change do
    drop(unique_index(:votes, [:dashboard_id]))
    create(unique_index(:votes, [:dashboard_id, :user_id]))
  end
end
