defmodule Sanbase.Repo.Migrations.AddMetricsJsonFieldChartConfiguration do
  use Ecto.Migration

  def change do
    alter table("chart_configurations") do
      add(:metrics_json, :jsonb)
    end
  end
end
