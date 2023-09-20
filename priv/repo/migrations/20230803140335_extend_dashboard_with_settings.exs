defmodule Sanbase.Repo.Migrations.ExtendDashboardWithSettings do
  use Ecto.Migration

  def change do
    alter table(:dashboards) do
      add(:settings, :jsonb, default: "{}")
    end
  end
end
