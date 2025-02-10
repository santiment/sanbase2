defmodule Sanbase.Repo.Migrations.RemoveTempJsonFromDashboard do
  @moduledoc false
  use Ecto.Migration

  def up do
    alter table(:dashboards) do
      remove(:temp_json)
    end
  end

  def down do
    alter table(:dashboards) do
      add(:temp_json, :map, default: "{}")
    end
  end
end
