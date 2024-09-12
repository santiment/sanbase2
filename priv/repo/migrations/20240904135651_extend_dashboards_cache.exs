defmodule Sanbase.Repo.Migrations.ExtendDashboardsCache do
  use Ecto.Migration

  def change do
    alter table(:dashboards_cache) do
      add(:parameters_override_hash, :string, null: false, default: "none")
    end

    drop(unique_index("dashboards_cache", [:dashboard_id]))
    create(unique_index("dashboards_cache", [:dashboard_id, :parameters_override_hash]))
  end
end
