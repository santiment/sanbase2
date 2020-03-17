defmodule Sanbase.Repo.Migrations.AddChartConfigurationDrawings do
  use Ecto.Migration
  @table "chart_configurations"
  def change do
    alter table(@table) do
      add(:drawings, :jsonb)
    end
  end
end
