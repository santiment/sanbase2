defmodule Sanbase.Repo.Migrations.AddAvailableMetricsLookbackDaysToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:available_metrics_lookback_days, :integer, null: true)
    end
  end
end
