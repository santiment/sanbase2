defmodule Sanbase.Repo.Migrations.AddDashboardCreditsTable do
  use Ecto.Migration

  def change do
    create table(:dashboard_credits) do
      add(:user_id, references(:users, on_delete: :delete_all))

      add(:dashboard_id, references(:dashboards, on_delete: :delete_all))
      add(:panel_id, :string, null: false)

      add(:query_id, :string, null: false)
      add(:query_data, :map, null: false)
      add(:credits_cost, :integer, null: false)

      timestamps()
    end
  end
end
