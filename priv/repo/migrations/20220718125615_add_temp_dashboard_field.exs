defmodule Sanbase.Repo.Migrations.AddTempDashboardField do
  use Ecto.Migration

  def change do
    alter table(:dashboards) do
      add(:temp_json, :map, default: "{}")
    end
  end
end
