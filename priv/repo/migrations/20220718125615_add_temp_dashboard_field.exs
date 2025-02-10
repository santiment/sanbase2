defmodule Sanbase.Repo.Migrations.AddTempDashboardField do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:dashboards) do
      add(:temp_json, :map, default: "{}")
    end
  end
end
