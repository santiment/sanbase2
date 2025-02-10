defmodule Sanbase.Repo.Migrations.AddDashboardParameters do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:dashboards) do
      add(:parameters, :map, default: "{}")
    end

    alter table(:dashboards_history) do
      add(:parameters, :map, default: "{}")
    end
  end
end
