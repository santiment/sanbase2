defmodule Sanbase.Repo.Migrations.AddChartConfigurationQueries do
  use Ecto.Migration

  def change do
    alter table(:chart_configurations) do
      add(:queries, :jsonb)
    end
  end
end
