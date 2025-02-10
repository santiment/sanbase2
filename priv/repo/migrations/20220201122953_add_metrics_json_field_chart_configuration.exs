defmodule Sanbase.Repo.Migrations.AddMetricsJsonFieldChartConfiguration do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table("chart_configurations") do
      add(:metrics_json, :map, default: %{})
    end
  end
end
