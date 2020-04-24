defmodule Sanbase.Repo.Migrations.AddOptionsToChartConfigurations do
  use Ecto.Migration

  def change do
    alter table("chart_configurations") do
      add(:options, :jsonb)
    end
  end
end
